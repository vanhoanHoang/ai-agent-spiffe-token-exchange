#!/usr/bin/env bash
# M10 P2.5 exit criterion (DEMO-PLAN P2.5), on the ONE interface (P6.3 — the
# console at /):
#  - Scripted authorization-code login (curl through the Keycloak login form,
#    cookie jar, PKCE, CONSENT accepted — the delegation moment, forced fresh
#    every run), then a chat POST, produces an MCP call whose server log shows
#    sub=alice and act.sub = the agent's SPIFFE ID.
#  - Login ENDS on the console root — there is no second interface.
#  - No access token appears in ANY browser-visible response.
#  - ./infra/acceptance.sh still exits 0, untouched.
#
# Host-side note: the issuer is http://keycloak:8080 (D-005); this script maps
# that hostname to localhost via curl --resolve. A human browser needs the
# equivalent hosts-file line (demo/checklist.sh checks it).
set -euo pipefail
cd "$(dirname "$0")/.."
fail() { echo "P25 FAIL: $1"; exit 1; }

KC=http://localhost:8080
WEB=http://localhost:8090
AGENT_ID=spiffe://lab.internal/agent-client
JWT_RE='[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}'
RESOLVE=(--resolve keycloak:8080:127.0.0.1)

bash infra/pki/issue-bundle-endpoint-cert.sh >/dev/null
(cd infra && docker compose up -d --wait spire-server spire-agent keycloak) >/dev/null || fail "core stack not healthy"
bash infra/spire/register-workloads.sh >/dev/null
bash infra/keycloak/setup-realm.sh >/dev/null
bash infra/keycloak/setup-spiffe-idp.sh >/dev/null || fail "keycloak setup failed"
bash infra/keycloak/setup-demo-web.sh >/dev/null || fail "demo-web setup failed"
(cd infra && docker compose --profile demo up -d --wait --wait-timeout 300) >/dev/null || fail "stack (incl. agent-web) not healthy"
bash infra/ollama/pull-model.sh >/dev/null || fail "demo model pull failed"

K() { MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker compose -f infra/docker-compose.yml exec -T keycloak /opt/keycloak/bin/kcadm.sh "$@"; }
K config credentials --server http://localhost:8080 --realm master --user admin --password admin >/dev/null 2>&1
ALICE_ID=$(K get users -r lab -q username=alice --fields id 2>/dev/null | tr -d ' \n' | sed 's/.*"id":"\([^"]*\)".*/\1/')
ALICE_SUB=$ALICE_ID
# Force the consent moment every run (dev-file store may remember the grant).
K delete "users/$ALICE_ID/consents/demo-web" -r lab >/dev/null 2>&1 || true

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
JAR="$WORK/cookies.txt"
save() { tee "$WORK/$1" ; }
# Keycloak renders some form actions relative — qualify them against the issuer.
form_action() {
  local a
  a=$(grep -o 'action="[^"]*"' "$1" | head -1 | cut -d'"' -f2 | sed 's/&amp;/\&/g')
  case "$a" in /*) a="http://keycloak:8080$a" ;; esac
  printf '%s' "$a"
}

# 1) The ONE interface: the console at the root, logged out, offering login.
curl -s -c "$JAR" "$WEB/" | save front.html | grep -q '<dc-root>' \
  || fail "the root does not serve the console"
code=$(curl -s -b "$JAR" -o /dev/null -w '%{http_code}' "$WEB/api/me")
[ "$code" = 401 ] || fail "/api/me logged out expected 401, got $code"
echo "OK: the console IS the interface; /api/me honest when logged out"

# 2) Authorization-code flow -> Keycloak login form.
curl -s -b "$JAR" -c "$JAR" -L "${RESOLVE[@]}" "$WEB/oauth2/authorization/keycloak" | save login.html >/dev/null
ACTION=$(form_action "$WORK/login.html")
[ -n "$ACTION" ] || fail "no login form action found"
echo "$ACTION" | grep -q "login-actions" || fail "unexpected login form action: $ACTION"

# 3) Post alice's credentials.
curl -s -b "$JAR" -c "$JAR" -L "${RESOLVE[@]}" \
  -d username=alice -d password=alice-password "$ACTION" | save after-login.html >/dev/null

# 4) Consent screen — the delegation moment (generic form replay).
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
  FINAL=$(curl -s -b "$JAR" -c "$JAR" -L "${RESOLVE[@]}" "${CARGS[@]}" -d accept=Yes \
    -o "$WORK/after-consent.html" -w '%{url_effective}' "$CACTION")
  echo "OK: consent screen shown and accepted"
else
  fail "consent screen did not appear (consentRequired must make delegation explicit)"
fi
[ "$FINAL" = "$WEB/" ] || fail "login did not end on the console root: $FINAL"
echo "OK: login ends on the console root (one interface)"

# 5) /api/me identifies alice; CSRF for the chat POST.
ME=$(curl -s -b "$JAR" "$WEB/api/me")
echo "$ME" | save me.json | grep -q '"username":"alice"' || fail "/api/me after login: $ME"
CSRF=$(echo "$ME" | grep -o '"csrf":"[^"]*"' | cut -d'"' -f4)
[ -n "$CSRF" ] || fail "no CSRF token from /api/me"

# 6) Chat: natural language -> MCP call, asserted in the server log.
T0=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
curl -s -b "$JAR" --max-time 300 -H "Content-Type: application/json" -H "X-CSRF-TOKEN: $CSRF" \
  -d '{"message":"Use the whoami tool, then state which workload and which human you are acting for."}' \
  "$WEB/api/chat" | save chat.json >/dev/null
grep -q '"answer"' "$WORK/chat.json" || fail "chat lacks answer: $(head -c 300 "$WORK/chat.json")"
logs=$(cd infra && docker compose logs --since "$T0" mcp-server 2>/dev/null)
echo "$logs" | grep "tool=whoami" | grep "sub=$ALICE_SUB" | grep -q "act={sub=$AGENT_ID}" \
  || fail "server log since $T0 lacks tool=whoami with sub=$ALICE_SUB and act.sub=$AGENT_ID"
echo "OK: browser chat produced MCP call; server logged sub=alice act.sub=$AGENT_ID"

# 7) Token hygiene: nothing JWT-shaped in anything the browser ever received.
if grep -hE "$JWT_RE" "$WORK"/front.html "$WORK"/me.json "$WORK"/chat.json "$WORK"/after-consent.html >/dev/null 2>&1; then
  fail "a token-shaped string reached the browser"
fi
echo "OK: no access token in any browser-visible response"

git diff --quiet HEAD -- infra/acceptance.sh || fail "acceptance.sh was modified"
bash infra/acceptance.sh >/dev/null 2>&1 || fail "acceptance.sh no longer exits 0"
echo "OK: acceptance.sh untouched and still green"
echo "P25 PASS"
