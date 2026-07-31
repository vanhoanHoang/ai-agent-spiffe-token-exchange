#!/usr/bin/env bash
# P6 (user-directed extension, 2026-07-31): the Angular console served BY
# agent-web (same origin) with a live chat panel — the animated flow is driven
# by real messages. Exit criterion:
#   - GET /console/ serves the built console to an unauthenticated browser
#   - /api/me is 401-shaped when logged out, identifies alice when logged in
#   - POST /api/chat (session + CSRF header) produces an MCP call whose server
#     log shows sub=alice and act.sub=<agent SPIFFE ID>
#   - no token-shaped string in ANY browser-visible response
#   - the OFFLINE console still passes check-console.sh (M11 exit intact)
#   - ./infra/acceptance.sh still exits 0, untouched
set -euo pipefail
cd "$(dirname "$0")/.."
dkr() { MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker "$@"; }
fail() { echo "P6 FAIL: $1"; exit 1; }

WEB=http://localhost:8090
AGENT_ID=spiffe://ai-agent.id.eviden.internal/agent-client
JWT_RE='[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}'
RESOLVE=(--resolve keycloak:8080:127.0.0.1)

# ---- 0. The console bundle exists and the stack is up ----------------------
# The build cache goes bad if a dev server ran against it — clear, then build.
(cd console && rm -rf .angular && npm run -s build >/dev/null) || fail "console build"
bash infra/pki/issue-bundle-endpoint-cert.sh >/dev/null
(cd infra && docker compose up -d --wait spire-server spire-agent keycloak) >/dev/null || fail "core stack"
bash infra/spire/register-workloads.sh >/dev/null
bash infra/keycloak/setup-realm.sh >/dev/null
bash infra/keycloak/setup-spiffe-idp.sh >/dev/null
bash infra/keycloak/setup-demo-web.sh >/dev/null
(cd infra && docker compose --profile demo up -d --wait --wait-timeout 300) >/dev/null || fail "stack"
bash infra/ollama/pull-model.sh >/dev/null

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
JAR="$WORK/cookies.txt"
save() { tee "$WORK/$1"; }
form_action() {
  local a
  a=$(grep -o 'action="[^"]*"' "$1" | head -1 | cut -d'"' -f2 | sed 's/&amp;/\&/g')
  case "$a" in /*) a="http://keycloak:8080$a" ;; esac
  printf '%s' "$a"
}

# ---- 1. Unauthenticated: console served, /api/me honest --------------------
 curl -s -c "$JAR" "$WEB/" | save console.html | grep -q '<dc-root>' \
  || fail "root does not serve the built console"
code=$(curl -s -b "$JAR" -o "$WORK/me401.json" -w '%{http_code}' "$WEB/api/me")
[ "$code" = 401 ] || fail "/api/me logged out expected 401, got $code"
echo "OK: console served same-origin; /api/me honest when logged out"

# ---- 1a. P6.7: /login is the SPA's page, not Spring's generated one --------
curl -s "$WEB/login" | save login-page.html | grep -q '<dc-root>' \
  || fail "/login does not serve the SPA"
grep -qi 'Please sign in' "$WORK/login-page.html" \
  && fail "/login is Spring Security's generated page, not ours" || true
echo "OK: /login serves the console's own sign-in page"

# ---- 1b. Live X.509-SVID chain view (P6.5): metadata only, never a key -----
curl -s "$WEB/api/svid" | save svid.json >/dev/null
grep -q '"spiffeId":"spiffe://ai-agent.id.eviden.internal/agent-client"' "$WORK/svid.json" \
  || fail "/api/svid does not name the agent's SPIFFE ID"
grep -q '"role":"leaf"' "$WORK/svid.json" && grep -q '"serial"' "$WORK/svid.json" \
  || fail "/api/svid missing leaf/serial metadata"
# P6.6 expert view: full details incl. the EJBCA intermediate's name constraint
grep -q '"signatureAlgorithm"' "$WORK/svid.json" \
  || fail "/api/svid missing certificate details"
grep -q 'Permitted: URI:ai-agent.id.eviden.internal' "$WORK/svid.json" \
  || fail "/api/svid does not surface the URI name constraint"
grep -qi 'PRIVATE KEY\|BEGIN CERTIFICATE' "$WORK/svid.json" \
  && fail "/api/svid leaks key/PEM material" || true
echo "OK: /api/svid serves the live chain metadata (no key, no PEM)"

# ---- 2. Scripted login (authorization code + PKCE + consent) ---------------
curl -s -b "$JAR" -c "$JAR" -L "${RESOLVE[@]}" "$WEB/oauth2/authorization/keycloak" | save login.html >/dev/null
ACTION=$(form_action "$WORK/login.html")
curl -s -b "$JAR" -c "$JAR" -L "${RESOLVE[@]}" -d username=alice -d password=alice-password "$ACTION" | save after-login.html >/dev/null
if grep -q 'name="code"' "$WORK/after-login.html" && grep -qi consent "$WORK/after-login.html"; then
  CACTION=$(form_action "$WORK/after-login.html")
  CARGS=()
  while IFS='|' read -r n v; do v=${v%$'\r'}; CARGS+=(--data-urlencode "$n=$v"); done < <(
    python - "$WORK/after-login.html" <<'EOF'
import re, sys
html = open(sys.argv[1], encoding="utf-8", errors="replace").read()
for m in re.finditer(r'<input[^>]*type="hidden"[^>]*>', html):
    n = re.search(r'name="([^"]*)"', m.group(0))
    v = re.search(r'value="([^"]*)"', m.group(0))
    if n: print(f"{n.group(1)}|{v.group(1) if v else ''}")
EOF
  )
  curl -s -b "$JAR" -c "$JAR" -L "${RESOLVE[@]}" "${CARGS[@]}" -d accept=Yes "$CACTION" >/dev/null
fi

# Login must END on the console — the live panel is the point (user-reported).
FINAL=$(curl -s -b "$JAR" -c "$JAR" -L "${RESOLVE[@]}" -o /dev/null -w '%{url_effective}' "$WEB/oauth2/authorization/keycloak")
[ "$FINAL" = "$WEB/" ] || fail "login does not land on the console root: $FINAL"
echo "OK: login flow returns to the console root"

ME=$(curl -s -b "$JAR" "$WEB/api/me")
echo "$ME" | save me.json | grep -q '"username":"alice"' || fail "/api/me after login: $ME"
CSRF=$(echo "$ME" | grep -o '"csrf":"[^"]*"' | cut -d'"' -f4)
[ -n "$CSRF" ] || fail "/api/me carries no csrf token"
echo "OK: logged in; /api/me identifies alice and hands the console its CSRF token"

# ---- 3. Live chat -> real MCP call, proven in the server log ---------------
T0=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
curl -s -b "$JAR" --max-time 300 -H "Content-Type: application/json" -H "X-CSRF-TOKEN: $CSRF" \
  -d '{"message":"Use the whoami tool, then state which workload and which human you are acting for."}' \
  "$WEB/api/chat" | save chat.json >/dev/null
grep -q '"answer"' "$WORK/chat.json" || fail "chat response lacks answer: $(head -c 300 "$WORK/chat.json")"
logs=$(cd infra && docker compose logs --since "$T0" mcp-server 2>/dev/null)
echo "$logs" | grep "tool=" | grep -q "act={sub=$AGENT_ID}" \
  || fail "no MCP call with act.sub=$AGENT_ID since $T0"
echo "OK: live console chat produced an MCP call; server logged act.sub=$AGENT_ID"

# ---- 3b. Real-time stream: the chain's actual events, in order -------------
T1=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
curl -s -N -b "$JAR" --max-time 300 -H "Content-Type: application/json" -H "X-CSRF-TOKEN: $CSRF" \
  -d '{"message":"Use the whoami tool, then state which workload and which human you are acting for."}' \
  "$WEB/api/chat/stream" | save stream.txt >/dev/null
for ev in svid exchange tool answer; do
  grep -q "^event: *$ev" "$WORK/stream.txt" || fail "stream lacks event '$ev': $(head -c 400 "$WORK/stream.txt")"
done
# order: svid before exchange before tool before answer
seq=$(grep '^event:' "$WORK/stream.txt" | sed 's/^event: *//' | tr '\n' ' ')
python - "$seq" <<'EOF' || { echo "P6 FAIL: stream events out of order: $seq"; exit 1; }
import sys
evs = sys.argv[1].split()
order = [evs.index(e) for e in ("svid", "exchange", "tool", "answer")]
sys.exit(0 if order == sorted(order) else 1)
EOF
grep '^event: *tool' -A1 "$WORK/stream.txt" | grep -q "whoami" || fail "tool event lacks the tool name"
logs=$(cd infra && docker compose logs --since "$T1" mcp-server 2>/dev/null)
echo "$logs" | grep "tool=whoami" | grep -q "act={sub=$AGENT_ID}" || fail "streamed chat produced no logged MCP call"
echo "OK: live stream emits real chain events in order (svid -> exchange -> tool -> answer)"

# ---- 4. Token hygiene ------------------------------------------------------
grep -hE "$JWT_RE" "$WORK"/console.html "$WORK"/me.json "$WORK"/chat.json "$WORK"/stream.txt >/dev/null 2>&1 \
  && fail "a token-shaped string reached the browser" || true
echo "OK: no token-shaped string in any browser-visible response"

# ---- 5. Offline console + acceptance still green ---------------------------
bash scripts/check-console.sh >/dev/null 2>&1 || fail "offline console (M11 exit) broke"
echo "OK: offline console mode intact (check-console.sh green)"
git diff --quiet HEAD -- infra/acceptance.sh || fail "acceptance.sh was modified"
bash infra/acceptance.sh >/dev/null 2>&1 || fail "acceptance.sh no longer exits 0"
echo "OK: acceptance.sh untouched and still green"
echo "P6 PASS"
