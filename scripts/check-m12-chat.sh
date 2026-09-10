#!/usr/bin/env bash
# The two-hop use case, DRIVEN BY THE CHATBOX (user-directed, post-D-034).
#
# check-m12.sh already proves the chain works when a script drives it. This
# proves the thing the demo actually shows: alice types one sentence into the
# console and the whole delegation happens, visibly, with the console able to
# tell hop 1 from hop 2.
#
#   1. alice logs in through the browser flow and CONSENTS to both task scopes.
#   2. She sends one sentence. The model picks onboard_employee by itself.
#   3. The stream carries TWO svid+exchange pairs — the console derives the hop
#      boundary from exactly that (console/src/app/core/hops.ts), so two pairs
#      is what makes the second hop visible rather than merely real.
#   4. A real certificate is issued and cert-service logs the NESTED chain.
#   5. The assistant's own token still cannot issue. The hop stays required.
set -uo pipefail
cd "$(dirname "$0")/.."
fail() { echo "M12-CHAT FAIL: $1"; exit 1; }

WEB=http://localhost:8090
KC=http://localhost:8080
TD=spiffe://ai-agent.id.eviden.internal
RESOLVE=(--resolve keycloak:8080:127.0.0.1)
dkr() { MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker "$@"; }

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
JAR="$WORK/cookies.txt"
# A relative form action must resolve against the KEYCLOAK host, not localhost:
# the session cookies were set for keycloak:8080 (--resolve maps it here), and
# posting to localhost drops them — the login silently ends up unauthenticated.
form_action() {
  local a
  a=$(grep -o 'action="[^"]*"' "$1" | head -1 | cut -d'"' -f2 | sed 's/&amp;/\&/g')
  case "$a" in /*) a="http://keycloak:8080$a" ;; esac
  printf '%s' "$a"
}

accept_form() { # $1 = html file holding a Keycloak form with hidden inputs
  local caction cargs=()
  caction=$(form_action "$1")
  while IFS='|' read -r n v; do v=${v%$'\r'}; cargs+=(--data-urlencode "$n=$v"); done < <(
    python - "$1" <<'EOF'
import re, sys
html = open(sys.argv[1], encoding="utf-8", errors="replace").read()
for m in re.finditer(r'<input[^>]*type="hidden"[^>]*>', html):
    n = re.search(r'name="([^"]*)"', m.group(0))
    v = re.search(r'value="([^"]*)"', m.group(0))
    if n: print(f"{n.group(1)}|{v.group(1) if v else ''}")
EOF
  )
  curl -s -b "$JAR" -c "$JAR" -L "${RESOLVE[@]}" "${cargs[@]}" -d accept=Yes "$caction" >/dev/null
}

# M15 (consent-on-demand): login grants identity only; the task scopes arrive
# through the step-up leg. This check drives both, then proves the chain —
# what it asserts about the chain itself is unchanged.
echo "== alice signs in (identity), then steps up to both task scopes =="
curl -s -b "$JAR" -c "$JAR" -L "${RESOLVE[@]}" "$WEB/oauth2/authorization/keycloak" > "$WORK/login.html"
ACTION=$(form_action "$WORK/login.html")
[ -n "$ACTION" ] || fail "no login form at the authorization endpoint"
curl -s -b "$JAR" -c "$JAR" -L "${RESOLVE[@]}" \
  -d username=alice -d password=alice-password "$ACTION" > "$WORK/after-login.html"
if grep -q 'name="code"' "$WORK/after-login.html" && grep -qi consent "$WORK/after-login.html"; then
  accept_form "$WORK/after-login.html"
fi
curl -s -b "$JAR" -c "$JAR" -L "${RESOLVE[@]}" "$WEB/oauth2/authorization/keycloak-elevate" > "$WORK/elevate.html"
if grep -qi consent "$WORK/elevate.html"; then
  # The step-up consent must OFFER both task scopes — if it does not, alice
  # has nothing to delegate and the whole use case is unreachable.
  grep -q 'onboard:initiate\|Onboard' "$WORK/elevate.html" \
    || fail "step-up consent does not offer onboard:initiate — alice cannot delegate"
  accept_form "$WORK/elevate.html"
fi

ME=$(curl -s -b "$JAR" "$WEB/api/me")
echo "$ME" | grep -q '"username":"alice"' || fail "not logged in: $ME"
echo "$ME" | grep -q 'onboard:initiate' || fail "alice's session lacks onboard:initiate: $ME"
echo "$ME" | grep -q 'issue:employee-cert' || fail "alice's session lacks issue:employee-cert: $ME"
CSRF=$(echo "$ME" | grep -o '"csrf":"[^"]*"' | cut -d'"' -f4)
[ -n "$CSRF" ] || fail "no csrf token"
echo "OK: alice is signed in and granted both task scopes"

echo
echo "== one sentence in the chatbox =="
T0=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
curl -s -N -b "$JAR" --max-time 900 -H "Content-Type: application/json" -H "X-CSRF-TOKEN: $CSRF" \
  -d '{"message":"Onboard John. He starts Monday. His device is john-laptop."}' \
  "$WEB/api/chat/stream" > "$WORK/stream.txt"
grep -q '^event: *answer' "$WORK/stream.txt" \
  || fail "no answer from the chat stream: $(head -c 400 "$WORK/stream.txt")"
echo "OK: the chat answered"

echo
echo "== the stream shows TWO hops, not one =="
SVIDS=$(grep -c '^event: *svid' "$WORK/stream.txt")
EXCH=$(grep -c '^event: *exchange' "$WORK/stream.txt")
[ "$SVIDS" -ge 2 ] || fail "only $SVIDS svid event(s) — the console cannot see a second hop: $(grep '^event:' "$WORK/stream.txt" | tr '\n' ' ')"
[ "$EXCH" -ge 2 ] || fail "only $EXCH exchange event(s) — the second hop never happened"
grep -A1 '^event: *tool' "$WORK/stream.txt" | grep -q 'onboard_employee' \
  || fail "the model never called onboard_employee: $(grep -A1 '^event: *tool' "$WORK/stream.txt" | head -8)"
grep -q "$TD/agent-pki" "$WORK/stream.txt" \
  || fail "the stream never names agent-pki — hop 2 is not attributable"
echo "OK: two svid+exchange pairs, agent-pki named, onboard_employee called by the model"

echo
echo "== a real certificate, with the nested chain =="
logs=$(dkr logs --since "$T0" spiffe-mcp-lab-cert-service-1 2>&1)
echo "$logs" | grep -q "ISSUED" || fail "cert-service issued nothing since $T0"
line=$(echo "$logs" | grep "ISSUED" | tail -1)
echo "$line" | grep -q "agent-pki" || fail "chain does not name agent-pki: $line"
echo "$line" | grep -q "agent-client" || fail "chain is NOT NESTED — agent-client missing: $line"
echo "OK: $(echo "$line" | grep -o 'cn=[^ ]*') issued, chain nested agent-pki <- agent-client"

echo
echo "== the hop is still required =="
# No token-shaped string may reach the browser, and the assistant must still be
# unable to obtain the issuing scope on its own.
grep -qE '[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}' "$WORK/stream.txt" \
  && fail "a token-shaped string reached the browser" || true
TOKEN_EP="$KC/realms/ai-agents/protocol/openid-connect/token"
USER_TOKEN=$(curl -s -d grant_type=password -d client_id=test-caller -d username=alice -d password=alice-password \
  -d 'scope=openid onboard:initiate issue:employee-cert' "$TOKEN_EP" \
  | grep -o '"access_token":"[^"]*"' | head -1 | cut -d'"' -f4)
SVID=$(dkr run --rm --label org.lab.workload=agent-client --network spiffe-mcp-lab_lab \
  -v spiffe-mcp-lab_spire-agent-socket:/tmp/spire-agent/public:ro \
  -e SPIFFE_ENDPOINT_SOCKET=unix:/tmp/spire-agent/public/api.sock \
  spiffe-mcp-lab-agent-client svid "http://keycloak:8080/realms/ai-agents" 2>&1 \
  | grep -o 'ey[A-Za-z0-9._-]*' | head -1 | tr -d '\r\n')
ESC=$(curl -s -d grant_type=urn:ietf:params:oauth:grant-type:token-exchange \
  -d subject_token="$USER_TOKEN" -d subject_token_type=urn:ietf:params:oauth:token-type:access_token \
  --data-urlencode client_id="$TD/agent-client" \
  --data-urlencode client_assertion_type="urn:ietf:params:oauth:client-assertion-type:jwt-spiffe" \
  --data-urlencode client_assertion="$SVID" -d scope="issue:employee-cert" "$TOKEN_EP")
echo "$ESC" | grep -q '"access_token"' \
  && fail "the assistant obtained issue:employee-cert — one agent could do it all"
echo "OK: the assistant still cannot obtain the issuing scope"

echo
echo "M12-CHAT PASS"
