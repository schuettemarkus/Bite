#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# Bite QA Test Suite — run before and after deployments
# Usage:
#   ./qa.sh https://bite-worker.schuette-markus.workers.dev
#   ./qa.sh http://localhost:8787
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

BASE="${1:?Usage: ./qa.sh <worker-base-url>}"
PASS=0
FAIL=0
TOTAL=0

green() { printf "\033[32m✓ %s\033[0m\n" "$1"; }
red()   { printf "\033[31m✗ %s\033[0m\n" "$1"; }
gray()  { printf "\033[90m  %s\033[0m\n" "$1"; }

check() {
  TOTAL=$((TOTAL + 1))
  local name="$1"
  local result="$2"
  if [ "$result" = "true" ]; then
    PASS=$((PASS + 1))
    green "$name"
  else
    FAIL=$((FAIL + 1))
    red "$name"
  fi
}

echo ""
echo "��══════════════════════════════════════════════════"
echo "  Bite QA Suite — $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Target: $BASE"
echo "═══════════════════════════════════════════════════"
echo ""

# ─── 1. Health check ──────────────────────────────────
echo "── Worker Health ──"
HEALTH=$(curl -sf "$BASE/health" 2>/dev/null || echo '{}')
check "Health endpoint returns ok" "$(echo "$HEALTH" | grep -q '"ok":true' && echo true || echo false)"

# ─── 2. Nearby search ────────────────────────────────
echo ""
echo "── Nearby Search (SF) ──"
NEARBY=$(curl -sf "$BASE/api/nearby?lat=37.7749&lng=-122.4194" 2>/dev/null || echo '{}')
HAS_RESTAURANTS=$(echo "$NEARBY" | grep -q '"restaurants":\[' && echo true || echo false)
check "Nearby returns restaurant array" "$HAS_RESTAURANTS"

# Check all ratings >= 4.0
if [ "$HAS_RESTAURANTS" = "true" ]; then
  BAD_RATINGS=$(echo "$NEARBY" | python3 -c "
import json, sys
data = json.load(sys.stdin)
bad = [r for r in data.get('restaurants', []) if r.get('rating', 0) < 4.0]
print(len(bad))
" 2>/dev/null || echo "0")
  check "All ratings >= 4.0" "$([ "$BAD_RATINGS" = "0" ] && echo true || echo false)"

  # Check required fields
  HAS_FIELDS=$(echo "$NEARBY" | python3 -c "
import json, sys
data = json.load(sys.stdin)
rs = data.get('restaurants', [])
if not rs: print('false'); sys.exit()
r = rs[0]
required = ['id','name','cuisine','rating','lat','lng']
print('true' if all(k in r for k in required) else 'false')
" 2>/dev/null || echo "false")
  check "Restaurant has required fields (id, name, cuisine, rating, lat, lng)" "$HAS_FIELDS"

  # Check no API key leaked
  NO_KEY=$(echo "$NEARBY" | grep -q 'AIza' && echo false || echo true)
  check "No API key in response body" "$NO_KEY"
fi

# ─── 3. Caching ──────────────────────────────────────
echo ""
echo "── Caching ──"
NEARBY2=$(curl -sf "$BASE/api/nearby?lat=37.7749&lng=-122.4194" 2>/dev/null || echo '{}')
IS_CACHED=$(echo "$NEARBY2" | grep -q '"cached":true' && echo true || echo false)
check "Second call returns cached:true" "$IS_CACHED"

# ─── 4. Geocode ──────────────────────────────────────
echo ""
echo "── Geocode ──"
GEO=$(curl -sf "$BASE/api/geocode?zip=94103" 2>/dev/null || echo '{}')
HAS_LAT=$(echo "$GEO" | grep -q '"lat"' && echo true || echo false)
check "Geocode returns lat/lng for ZIP 94103" "$HAS_LAT"

# ─── 5. Reverse geocode ─────────────────────────────
echo ""
echo "── Reverse Geocode ──"
REVGEO=$(curl -sf "$BASE/api/reverse-geocode?lat=37.7749&lng=-122.4194" 2>/dev/null || echo '{}')
HAS_NEIGHBORHOOD=$(echo "$REVGEO" | grep -q '"neighborhood"' && echo true || echo false)
check "Reverse geocode returns neighborhood" "$HAS_NEIGHBORHOOD"
HAS_CITY=$(echo "$REVGEO" | grep -q '"city"' && echo true || echo false)
check "Reverse geocode returns city" "$HAS_CITY"

# ─── 6. Photo proxy ─────────────────────────────────
echo ""
echo "── Photo Proxy ──"
if [ "$HAS_RESTAURANTS" = "true" ]; then
  PHOTO_PATH=$(echo "$NEARBY" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for r in data.get('restaurants', []):
    if r.get('imagePath'):
        print(r['imagePath']); sys.exit()
print('')
" 2>/dev/null || echo "")
  if [ -n "$PHOTO_PATH" ]; then
    PHOTO_STATUS=$(curl -sf -o /dev/null -w "%{http_code}" "$BASE$PHOTO_PATH" 2>/dev/null || echo "000")
    # 302 redirect or 200 are both fine
    check "Photo proxy returns 200 or 302" "$(echo "$PHOTO_STATUS" | grep -qE '^(200|302)$' && echo true || echo false)"
    # Ensure no API key in redirect URL
    PHOTO_HEADERS=$(curl -sf -I "$BASE$PHOTO_PATH" 2>/dev/null || echo "")
    NO_KEY_PHOTO=$(echo "$PHOTO_HEADERS" | grep -qi 'AIza' && echo false || echo true)
    check "No API key in photo redirect" "$NO_KEY_PHOTO"
  else
    gray "No photo path found in results — skipping photo proxy test"
  fi
else
  gray "No restaurants — skipping photo proxy test"
fi

# ─── 7. Frontend validation ──────────────────────────
echo ""
echo "── Frontend Validation ──"
FRONTEND_HTML="web/index.html"
if [ -f "$FRONTEND_HTML" ]; then
  # JS syntax validation via Node (authoritative — catches all syntax errors including async/await)
  JS_CONTENT=$(sed -n '/<script>/,/<\/script>/p' "$FRONTEND_HTML" | sed '1d;$d')
  JS_CHECK=$(echo "$JS_CONTENT" | node --check 2>&1; echo "EXIT:$?")
  JS_EXIT=$(echo "$JS_CHECK" | grep -o 'EXIT:[0-9]*' | cut -d: -f2)
  if [ "$JS_EXIT" = "0" ]; then
    check "Frontend JS syntax valid (node --check)" "true"
  else
    check "Frontend JS syntax valid (node --check)" "false"
    JS_ERR=$(echo "$JS_CHECK" | grep -v 'EXIT:' | head -3)
    gray "  $JS_ERR"
  fi

  # HTML well-formed check
  HTML_ERRORS=$(python3 -c "
from html.parser import HTMLParser
import sys
class Checker(HTMLParser):
    def __init__(self):
        super().__init__()
    def handle_starttag(self, tag, attrs): pass
    def handle_endtag(self, tag): pass
try:
    with open('$FRONTEND_HTML') as f:
        Checker().feed(f.read())
    print('OK')
except Exception as e:
    print(str(e)[:100])
" 2>/dev/null || echo "OK")
  check "HTML parses without errors" "$([ "$HTML_ERRORS" = "OK" ] && echo true || echo false)"

  # No hardcoded API keys (exact pattern for Google keys)
  LEAKED_KEY=$(grep -cE 'AIza[A-Za-z0-9_-]{30,}' "$FRONTEND_HTML" 2>/dev/null || echo "0")
  check "No API keys in frontend source" "$([ "$LEAKED_KEY" = "0" ] && echo true || echo false)"

  # Critical objects exist
  HAS_ROUTER=$(grep -c 'const Router' "$FRONTEND_HTML" 2>/dev/null || echo "0")
  HAS_APP=$(grep -c 'const App' "$FRONTEND_HTML" 2>/dev/null || echo "0")
  check "Router and App objects defined" "$([ "$HAS_ROUTER" -ge 1 ] && [ "$HAS_APP" -ge 1 ] && echo true || echo false)"

  # File size sanity (should be under 500KB for a single-file PWA)
  FILE_SIZE=$(wc -c < "$FRONTEND_HTML" 2>/dev/null || echo "0")
  check "Frontend under 500KB ($(( FILE_SIZE / 1024 ))KB)" "$([ "$FILE_SIZE" -lt 512000 ] && echo true || echo false)"
else
  gray "Frontend HTML not found at $FRONTEND_HTML — skipping"
fi

# ─── 8. Error handling ───────────────────────────────
echo ""
echo "── Error Handling ──"
BAD_COORDS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/api/nearby?lat=999&lng=999" 2>/dev/null || echo "000")
check "Invalid coords returns 400 (got $BAD_COORDS)" "$([ "$BAD_COORDS" = "400" ] && echo true || echo false)"

NOT_FOUND=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/api/nonexistent" 2>/dev/null || echo "000")
check "Unknown route returns 404 (got $NOT_FOUND)" "$([ "$NOT_FOUND" = "404" ] && echo true || echo false)"

# ─── 9. CORS ─────────────────────────────────────────
echo ""
echo "── CORS ──"
CORS_OK=$(curl -s -H "Origin: https://bite.pages.dev" -I "$BASE/health" 2>/dev/null | grep -qi 'access-control-allow-origin' && echo true || echo false)
check "CORS headers present for allowed origin" "$CORS_OK"

CORS_BAD=$(curl -s -H "Origin: https://evil.com" -o /dev/null -w "%{http_code}" "$BASE/api/nearby?lat=37&lng=-122" 2>/dev/null || echo "000")
check "Disallowed origin gets blocked (got $CORS_BAD)" "$([ "$CORS_BAD" = "403" ] && echo true || echo false)"

# ─── Summary ─────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════"
if [ "$FAIL" -eq 0 ]; then
  printf "\033[32m  All %d tests passed\033[0m\n" "$TOTAL"
else
  printf "\033[31m  %d/%d passed — %d failed\033[0m\n" "$PASS" "$TOTAL" "$FAIL"
fi
echo "═══════════════════════════════════════════════════"
echo ""

exit "$FAIL"
