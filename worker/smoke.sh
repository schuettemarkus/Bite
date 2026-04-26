#!/usr/bin/env bash
# Bite Worker — smoke test
# Hits every endpoint, validates response shape, checks rate limiting and CORS.
#
# Usage:
#   ./smoke.sh                          # tests local Worker at http://localhost:8787
#   ./smoke.sh https://bite-worker...   # tests deployed Worker
#
# Requires: curl, jq

set -uo pipefail

BASE="${1:-http://localhost:8787}"
ORIGIN="${ORIGIN:-http://localhost:5500}"

# Default to San Francisco if no coords specified.
LAT="${LAT:-37.7749}"
LNG="${LNG:-122.4194}"

# ── Color & status helpers ────────────────────────────────────────────
if [[ -t 1 ]]; then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'
  BLUE=$'\033[0;34m'; DIM=$'\033[2m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
else
  RED=; GREEN=; YELLOW=; BLUE=; DIM=; BOLD=; RESET=
fi

PASS=0; FAIL=0; TOTAL=0
declare -a FAILED_TESTS=()

ok()    { echo "  ${GREEN}✓${RESET} $1"; PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); }
fail()  { echo "  ${RED}✗${RESET} $1"; [[ -n "${2:-}" ]] && echo "    ${DIM}$2${RESET}"; FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); FAILED_TESTS+=("$1"); }
skip()  { echo "  ${YELLOW}⊘${RESET} $1 ${DIM}(skipped)${RESET}"; }
group() { echo; echo "${BOLD}${BLUE}▸ $1${RESET}"; }

# ── Preflight ─────────────────────────────────────────────────────────
echo "${BOLD}Bite Worker smoke test${RESET}"
echo "${DIM}Target: ${BASE}${RESET}"
echo "${DIM}Origin: ${ORIGIN}${RESET}"
echo "${DIM}Coords: ${LAT}, -${LNG}${RESET}"
echo

command -v jq >/dev/null 2>&1 || {
  echo "${RED}error:${RESET} jq is required (install: brew install jq | apt-get install jq)"
  exit 2
}

# ── Health ────────────────────────────────────────────────────────────
group "Health"

RESP=$(curl -s -w "\n%{http_code}" "$BASE/health" || echo "000")
BODY=$(echo "$RESP" | sed '$d'); CODE=$(echo "$RESP" | tail -n1)
if [[ "$CODE" == "200" ]] && echo "$BODY" | jq -e '.ok == true' >/dev/null 2>&1; then
  ok "GET /health returns 200 + {ok:true}"
else
  fail "GET /health" "expected 200 + {ok:true}, got $CODE: $BODY"
  echo
  echo "${RED}Worker doesn't appear to be running at $BASE.${RESET}"
  echo "${DIM}Start it with: cd worker && npm run dev${RESET}"
  exit 1
fi

# ── Nearby (cache miss + cache hit) ───────────────────────────────────
group "Nearby Search"

RESP=$(curl -s -w "\n%{http_code}" "$BASE/api/nearby?lat=$LAT&lng=-$LNG")
BODY=$(echo "$RESP" | sed '$d'); CODE=$(echo "$RESP" | tail -n1)

if [[ "$CODE" == "200" ]]; then
  ok "GET /api/nearby returns 200"
else
  fail "GET /api/nearby" "got $CODE: $(echo "$BODY" | head -c 200)"
fi

if echo "$BODY" | jq -e '.restaurants | type == "array"' >/dev/null 2>&1; then
  COUNT=$(echo "$BODY" | jq '.restaurants | length')
  ok "Response has restaurants array (${COUNT} items)"
else
  fail "Response shape" "missing or malformed .restaurants array"
fi

if [[ "${COUNT:-0}" -gt 0 ]]; then
  MIN_RATING=$(echo "$BODY" | jq '[.restaurants[].rating] | min')
  if (( $(echo "$MIN_RATING >= 4" | bc -l 2>/dev/null || echo 0) )); then
    ok "All restaurants have rating ≥ 4.0 (min: $MIN_RATING)"
  else
    fail "Rating filter" "found restaurant rated $MIN_RATING (expected ≥ 4.0)"
  fi

  REQUIRED_FIELDS='.id and .name and .cuisine and .rating and (.distance != null) and .priceLevel'
  if echo "$BODY" | jq -e ".restaurants[0] | $REQUIRED_FIELDS" >/dev/null 2>&1; then
    ok "First restaurant has required fields"
  else
    fail "Restaurant shape" "missing fields on first restaurant"
    echo "$BODY" | jq '.restaurants[0]' | head -20
  fi

  FIRST_ID=$(echo "$BODY" | jq -r '.restaurants[0].id')
  FIRST_PHOTO=$(echo "$BODY" | jq -r '.restaurants[0].imagePath // empty')
else
  skip "field shape checks (no restaurants returned)"
  FIRST_ID=""; FIRST_PHOTO=""
fi

# Cache hit verification
RESP2=$(curl -s "$BASE/api/nearby?lat=$LAT&lng=-$LNG")
if echo "$RESP2" | jq -e '.cached == true' >/dev/null 2>&1; then
  ok "Second request hits cache"
else
  fail "Cache" "expected .cached=true on second request"
fi

# ── Nearby — invalid coords ───────────────────────────────────────────
RESP=$(curl -s -w "\n%{http_code}" "$BASE/api/nearby?lat=999&lng=999")
CODE=$(echo "$RESP" | tail -n1)
if [[ "$CODE" == "400" ]]; then
  ok "Invalid coords return 400"
else
  fail "Invalid coords handling" "expected 400, got $CODE"
fi

# ── Place Details ─────────────────────────────────────────────────────
group "Place Details"

if [[ -n "$FIRST_ID" ]]; then
  RESP=$(curl -s -w "\n%{http_code}" "$BASE/api/place/$FIRST_ID")
  BODY=$(echo "$RESP" | sed '$d'); CODE=$(echo "$RESP" | tail -n1)
  if [[ "$CODE" == "200" ]] && echo "$BODY" | jq -e '.id and .displayName' >/dev/null 2>&1; then
    ok "GET /api/place/{id} returns place details"
  else
    fail "GET /api/place/{id}" "got $CODE"
  fi
else
  skip "place details (no id from nearby)"
fi

RESP=$(curl -s -w "\n%{http_code}" "$BASE/api/place/notavalidid!@#")
CODE=$(echo "$RESP" | tail -n1)
if [[ "$CODE" == "400" ]]; then
  ok "Invalid place id returns 400"
else
  fail "Invalid place id" "expected 400, got $CODE"
fi

# ── Photo proxy ───────────────────────────────────────────────────────
group "Photo proxy"

if [[ -n "$FIRST_PHOTO" ]]; then
  # imagePath looks like "/api/photo/places%2F..."
  RESP=$(curl -s -o /dev/null -w "%{http_code}|%{redirect_url}" "$BASE$FIRST_PHOTO")
  CODE="${RESP%|*}"; REDIRECT="${RESP#*|}"
  if [[ "$CODE" == "302" ]]; then
    ok "Photo endpoint returns 302 redirect"
    if [[ "$REDIRECT" == https://* ]] && [[ "$REDIRECT" != *"key="* ]]; then
      ok "Redirect URL contains no API key"
    else
      fail "Redirect URL" "API key may be exposed in redirect: $REDIRECT"
    fi
  else
    fail "Photo redirect" "expected 302, got $CODE"
  fi
else
  skip "photo proxy (no photo in nearby response)"
fi

RESP=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/api/photo/not-a-real-photo")
if [[ "$RESP" == "400" ]]; then
  ok "Invalid photo reference returns 400"
else
  fail "Invalid photo handling" "expected 400, got $RESP"
fi

# ── Geocode (forward) ─────────────────────────────────────────────────
group "Geocode"

RESP=$(curl -s -w "\n%{http_code}" "$BASE/api/geocode?zip=94103")
BODY=$(echo "$RESP" | sed '$d'); CODE=$(echo "$RESP" | tail -n1)
if [[ "$CODE" == "200" ]] && echo "$BODY" | jq -e '.lat and .lng' >/dev/null 2>&1; then
  ok "GET /api/geocode?zip=94103 returns coords"
  LAT_RESULT=$(echo "$BODY" | jq -r '.lat')
  if (( $(echo "$LAT_RESULT > 37 && $LAT_RESULT < 38" | bc -l 2>/dev/null || echo 0) )); then
    ok "Geocode returns SF-area coords"
  else
    fail "Geocode accuracy" "lat $LAT_RESULT not in SF range"
  fi
else
  fail "Geocode" "got $CODE: $(echo "$BODY" | head -c 200)"
fi

RESP=$(curl -s -w "\n%{http_code}" "$BASE/api/geocode?zip=$(printf 'a%.0s' {1..200})")
CODE=$(echo "$RESP" | tail -n1)
if [[ "$CODE" == "400" ]]; then
  ok "Overlong address returns 400"
else
  fail "Address validation" "expected 400 for 200-char address, got $CODE"
fi

# ── Reverse geocode ───────────────────────────────────────────────────
group "Reverse geocode"

RESP=$(curl -s -w "\n%{http_code}" "$BASE/api/reverse-geocode?lat=$LAT&lng=-$LNG")
BODY=$(echo "$RESP" | sed '$d'); CODE=$(echo "$RESP" | tail -n1)
if [[ "$CODE" == "200" ]] && echo "$BODY" | jq -e '. | has("neighborhood") or has("city")' >/dev/null 2>&1; then
  NEIGH=$(echo "$BODY" | jq -r '.neighborhood // .city // "—"')
  ok "Reverse geocode returns location: $NEIGH"
else
  fail "Reverse geocode" "got $CODE"
fi

# ── CORS ──────────────────────────────────────────────────────────────
group "CORS"

# Preflight from allowed origin
HEADERS=$(curl -s -o /dev/null -D - -X OPTIONS \
  -H "Origin: $ORIGIN" \
  -H "Access-Control-Request-Method: GET" \
  -H "Access-Control-Request-Headers: Content-Type" \
  "$BASE/api/nearby")
if echo "$HEADERS" | grep -qi "access-control-allow-origin: $ORIGIN"; then
  ok "Preflight from allowed origin returns Access-Control-Allow-Origin"
else
  fail "Preflight" "missing or wrong Access-Control-Allow-Origin header"
fi

# Disallowed origin should NOT get CORS headers (and may be 403)
HEADERS=$(curl -s -o /dev/null -D - -H "Origin: https://evil.example.com" "$BASE/api/nearby?lat=$LAT&lng=-$LNG")
if echo "$HEADERS" | grep -qi "access-control-allow-origin: https://evil"; then
  fail "Disallowed origin" "evil origin received CORS headers (security issue)"
else
  ok "Disallowed origin does not receive CORS headers"
fi

# ── Rate limit ────────────────────────────────────────────────────────
group "Rate limit"

echo "  ${DIM}firing 65 requests…${RESET}"
HIT_429=0
for i in $(seq 1 65); do
  CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/health")
  if [[ "$CODE" == "429" ]]; then HIT_429=1; break; fi
done
if [[ $HIT_429 -eq 1 ]]; then
  ok "Rate limit kicks in (429 received within 65 requests)"
else
  fail "Rate limit" "no 429 received in 65 requests — limiter may not be working"
fi

echo "  ${DIM}waiting 65s for rate limit window to clear…${RESET}"
sleep 65

# ── Summary ───────────────────────────────────────────────────────────
echo
echo "${BOLD}─────────────────────────────────────${RESET}"
if [[ $FAIL -eq 0 ]]; then
  echo "${GREEN}${BOLD}All $PASS tests passed.${RESET}"
  echo
  exit 0
else
  echo "${RED}${BOLD}$FAIL of $TOTAL tests failed:${RESET}"
  for t in "${FAILED_TESTS[@]}"; do echo "  ${RED}✗${RESET} $t"; done
  echo
  exit 1
fi
