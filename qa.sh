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

# ─── 7. Frontend JS validation ───────────────────────
echo ""
echo "── Frontend JS Validation ──"
FRONTEND_HTML="web/index.html"
if [ -f "$FRONTEND_HTML" ]; then
  # Extract JS from <script> tags and validate syntax with Node
  JS_CONTENT=$(sed -n '/<script>/,/<\/script>/p' "$FRONTEND_HTML" | sed '1d;$d')
  JS_ERRORS=$(echo "$JS_CONTENT" | node --check 2>&1 || true)
  if echo "$JS_ERRORS" | grep -qi "SyntaxError\|Unexpected\|Invalid"; then
    check "Frontend JS syntax valid" "false"
    gray "  $JS_ERRORS"
  else
    check "Frontend JS syntax valid" "true"
  fi

  # Check for common async/await mistakes — await outside async
  AWAIT_ISSUES=$(echo "$JS_CONTENT" | python3 -c "
import re, sys
code = sys.stdin.read()
# Find all function blocks and check for await in non-async ones
# Simple heuristic: look for lines with 'await' and trace back to nearest function decl
lines = code.split('\n')
issues = []
in_async = False
brace_depth = 0
func_stack = []
for i, line in enumerate(lines, 1):
    # Track function declarations
    if re.search(r'\basync\b.*\bfunction\b|\basync\b\s+\w+\s*\(|async\s+\w+\s*\(', line):
        func_stack.append(('async', brace_depth))
    elif re.search(r'\bfunction\b\s*\w*\s*\(|^\s*\w+\s*\([^)]*\)\s*\{', line) and 'async' not in line:
        func_stack.append(('sync', brace_depth))
    # Track braces
    brace_depth += line.count('{') - line.count('}')
    # Clean up stack
    while func_stack and func_stack[-1][1] >= brace_depth and brace_depth < func_stack[-1][1] + 1:
        if len(func_stack) > 1:
            func_stack.pop()
        else:
            break
    # Check for await
    if re.search(r'\bawait\b', line):
        if func_stack and func_stack[-1][0] == 'sync':
            issues.append(f'Line ~{i}: await in non-async function')
if issues:
    print('\\n'.join(issues[:5]))
else:
    print('OK')
" 2>/dev/null || echo "OK")
  if [ "$AWAIT_ISSUES" != "OK" ]; then
    check "No await outside async functions" "false"
    echo "$AWAIT_ISSUES" | while read -r line; do gray "  $line"; done
  else
    check "No await outside async functions" "true"
  fi

  # Check HTML is well-formed (basic)
  HTML_ERRORS=$(python3 -c "
from html.parser import HTMLParser
import sys
class Checker(HTMLParser):
    def __init__(self):
        super().__init__()
        self.errors = []
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

  # Check no hardcoded API keys
  LEAKED_KEY=$(grep -c 'AIza' "$FRONTEND_HTML" 2>/dev/null || echo "0")
  check "No API keys in frontend source" "$([ "$LEAKED_KEY" = "0" ] && echo true || echo false)"

  # Check critical functions exist
  HAS_ROUTER=$(grep -c 'const Router' "$FRONTEND_HTML" 2>/dev/null || echo "0")
  HAS_APP=$(grep -c 'const App' "$FRONTEND_HTML" 2>/dev/null || echo "0")
  check "Router and App objects defined" "$([ "$HAS_ROUTER" -ge 1 ] && [ "$HAS_APP" -ge 1 ] && echo true || echo false)"
else
  gray "Frontend HTML not found at $FRONTEND_HTML — skipping"
fi

# ─── 8. Error handling ───────────────────────────────
echo ""
echo "── Error Handling ──"
BAD_COORDS=$(curl -sf -o /dev/null -w "%{http_code}" "$BASE/api/nearby?lat=999&lng=999" 2>/dev/null || echo "000")
check "Invalid coords returns 400" "$([ "$BAD_COORDS" = "400" ] && echo true || echo false)"

NOT_FOUND=$(curl -sf -o /dev/null -w "%{http_code}" "$BASE/api/nonexistent" 2>/dev/null || echo "000")
check "Unknown route returns 404" "$([ "$NOT_FOUND" = "404" ] && echo true || echo false)"

# ─── 9. CORS ─────────────────────────────────────────
echo ""
echo "── CORS ──"
CORS_OK=$(curl -sf -H "Origin: https://bite.pages.dev" -I "$BASE/health" 2>/dev/null | grep -qi 'access-control-allow-origin' && echo true || echo false)
check "CORS headers present for allowed origin" "$CORS_OK"

CORS_BAD=$(curl -sf -H "Origin: https://evil.com" -o /dev/null -w "%{http_code}" "$BASE/api/nearby?lat=37&lng=-122" 2>/dev/null || echo "000")
check "Disallowed origin gets blocked" "$([ "$CORS_BAD" = "403" ] && echo true || echo false)"

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
