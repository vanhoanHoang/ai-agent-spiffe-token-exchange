#!/usr/bin/env bash
# M15 consent-on-demand: delegation authority is granted WHEN THE TASK NEEDS
# IT, not at the front door.
#
# The old flow front-loaded consent: entering the console demanded both task
# scopes before the user had typed a word, so the authorization moment was
# disconnected from the action it authorizes (the exact failure D-035 recorded
# from the other direction: widening consent at login broke the agent).
#
# Exit criterion, executable:
#   1. Signing in grants IDENTITY ONLY (openid profile) — the consent screen
#      must not offer a task scope, and the session must not carry one.
#   2. Asking the agent to onboard someone with zero task scopes must NOT run
#      the chain: the stream answers `consent` naming the missing scopes, no
#      exchange happens, no certificate is issued.
#   3. The step-up flow (keycloak-elevate) shows a consent screen that DOES
#      offer the task scopes; approving it upgrades the same session in place.
#   4. The SAME chat message then completes end-to-end: two svid+exchange
#      pairs, a real certificate, the nested chain — no re-login, no restart.
#   5. Enforcement never moved client-side: the AS still refuses the assistant
#      the issuing scope (unchanged from M12/M13; asserted there).
set -uo pipefail
cd "$(dirname "$0")/.."
fail() { echo "M15-CONSENT FAIL: $1"; exit 1; }

WEB=http://localhost:8090
TD=spiffe://ai-agent.id.eviden.internal
JWT_RE='[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}'
RESOLVE=(--resolve keycloak:8080:127.0.0.1)
dkr() { MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker "$@"; }

K() { MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker compose -f infra/docker-compose.yml exec -T keycloak /opt/keycloak/bin/kcadm.sh "$@"; }
K config credentials --server http://localhost:8080 --realm master --user admin --password admin >/dev/null 2>&1 \
  || fail "kcadm login failed — is the stack up?"
ALICE_ID=$(K get users -r ai-agents -q username=alice --fields id 2>/dev/null | tr -d ' \n' | sed 's/.*"id":"\([^"]*\)".*/\1/')
[ -n "$ALICE_ID" ] || fail "cannot resolve alice's user id"
# Force the consent moment every run (dev-file store may remember the grant).
K delete "users/$ALICE_ID/consents/demo-web" -r ai-agents >/dev/null 2>&1 || true

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
JAR="$WORK/cookies.txt"
form_action() {
  local a
  a=$(grep -o 'action="[^"]*"' "$1" | head -1 | cut -d'"' -f2 | sed 's/&amp;/\&/g')
  case "$a" in /*) a="http://keycloak:8080$a" ;; esac
  printf '%s' "$a"
}
hidden_inputs() {
  python - "$1" <<'EOF'
import re, sys
html = open(sys.argv[1], encoding="utf-8", errors="replace").read()
for m in re.finditer(r'<input[^>]*type="hidden"[^>]*>', html):
    n = re.search(r'name="([^"]*)"', m.group(0))
    v = re.search(r'value="([^"]*)"', m.group(0))
    if n: print(f"{n.group(1)}|{v.group(1) if v else ''}")
EOF
}
accept_consent() { # $1 = html file holding the consent form
  local caction cargs=()
  caction=$(form_action "$1")
  while IFS='|' read -r n v; do v=${v%$'\r'}; cargs+=(--data-urlencode "$n=$v"); done < <(hidden_inputs "$1")
  curl -s -b "$JAR" -c "$JAR" -L "${RESOLVE[@]}" "${cargs[@]}" -d accept=Yes "$caction" >/dev/null
}

echo "== 1. signing in asks for identity only =="
curl -s -b "$JAR" -c "$JAR" -L "${RESOLVE[@]}" "$WEB/oauth2/authorization/keycloak" > "$WORK/login.html"
ACTION=$(form_action "$WORK/login.html")
[ -n "$ACTION" ] || fail "no login form at the authorization endpoint"
curl -s -b "$JAR" -c "$JAR" -L "${RESOLVE[@]}" \
  -d username=alice -d password=alice-password "$ACTION" > "$WORK/after-login.html"
if grep -q 'name="code"' "$WORK/after-login.html" && grep -qi consent "$WORK/after-login.html"; then
  grep -qi 'onboard' "$WORK/after-login.html" \
    && fail "the LOGIN consent screen still offers onboard:initiate — consent is front-loaded"
  grep -qi 'employee-cert' "$WORK/after-login.html" \
    && fail "the LOGIN consent screen still offers issue:employee-cert — consent is front-loaded"
  accept_consent "$WORK/after-login.html"
fi
ME=$(curl -s -b "$JAR" "$WEB/api/me")
echo "$ME" | grep -q '"username":"alice"' || fail "not logged in: $ME"
echo "$ME" | grep -q 'onboard:initiate' && fail "session carries onboard:initiate at login: $ME"
echo "$ME" | grep -q 'issue:employee-cert' && fail "session carries issue:employee-cert at login: $ME"
CSRF=$(echo "$ME" | grep -o '"csrf":"[^"]*"' | cut -d'"' -f4)
[ -n "$CSRF" ] || fail "no csrf token"
echo "OK: alice is signed in with identity only — zero task scopes"

echo
echo "== 2. the task hits the wall: consent required, no chain, no cert =="
# The model runs and may exchange a token — with ZERO task scopes, which is
# the point (identity-only questions must keep working, P2.5). What must NOT
# happen: the chain-opening tool executing, or a certificate existing.
T0=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
MSG='{"message":"Onboard John. He starts Monday. His device is john-laptop."}'
curl -s -N -b "$JAR" --max-time 600 -H "Content-Type: application/json" -H "X-CSRF-TOKEN: $CSRF" \
  -d "$MSG" "$WEB/api/chat/stream" > "$WORK/refused.txt"
grep -q '^event: *consent' "$WORK/refused.txt" \
  || fail "no consent event — the agent ran (or died) instead of asking: $(grep '^event:' "$WORK/refused.txt" | tr '\n' ' ')"
grep -A1 '^event: *consent' "$WORK/refused.txt" | grep -q 'onboard:initiate' \
  || fail "consent event does not name the missing scope: $(grep -A1 '^event: *consent' "$WORK/refused.txt" | head -4)"
grep -A1 '^event: *tool' "$WORK/refused.txt" | grep -q 'onboard_employee' \
  && fail "onboard_employee EXECUTED with zero task scopes — the wall is not gating"
grep -A1 '^event: *exchange' "$WORK/refused.txt" | grep -q 'scope=.*onboard:initiate' \
  && fail "an exchanged token carries onboard:initiate the human never granted"
dkr logs --since "$T0" spiffe-mcp-lab-cert-service-1 2>&1 | grep -q "ISSUED" \
  && fail "a certificate was issued from an unconsented session"
echo "OK: the chain-opening tool refused up front — consent event names the missing scopes"

echo
echo "== 3. step-up consent offers the task scopes =="
curl -s -b "$JAR" -c "$JAR" -L "${RESOLVE[@]}" "$WEB/oauth2/authorization/keycloak-elevate" > "$WORK/elevate.html"
grep -qi consent "$WORK/elevate.html" || fail "no consent screen on step-up (SSO should skip the login form)"
grep -qi 'onboard' "$WORK/elevate.html" \
  || fail "step-up consent does not offer onboard:initiate"
grep -qi 'employee-cert' "$WORK/elevate.html" \
  || fail "step-up consent does not offer issue:employee-cert"
accept_consent "$WORK/elevate.html"
ME2=$(curl -s -b "$JAR" "$WEB/api/me")
echo "$ME2" | grep -q 'onboard:initiate' || fail "session still lacks onboard:initiate after step-up: $ME2"
echo "$ME2" | grep -q 'issue:employee-cert' || fail "session still lacks issue:employee-cert after step-up: $ME2"
CSRF=$(echo "$ME2" | grep -o '"csrf":"[^"]*"' | cut -d'"' -f4)
echo "OK: the same session now carries both task scopes"

echo
echo "== 4. the same sentence now completes end-to-end =="
T1=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
curl -s -N -b "$JAR" --max-time 900 -H "Content-Type: application/json" -H "X-CSRF-TOKEN: $CSRF" \
  -d "$MSG" "$WEB/api/chat/stream" > "$WORK/stream.txt"
grep -q '^event: *answer' "$WORK/stream.txt" \
  || fail "no answer after step-up: $(head -c 400 "$WORK/stream.txt")"
EXCH=$(grep -c '^event: *exchange' "$WORK/stream.txt")
[ "$EXCH" -ge 2 ] || fail "only $EXCH exchange event(s) after step-up — the second hop never happened"
logs=$(dkr logs --since "$T1" spiffe-mcp-lab-cert-service-1 2>&1)
echo "$logs" | grep -q "ISSUED" || fail "cert-service issued nothing after step-up"
line=$(echo "$logs" | grep "ISSUED" | tail -1)
echo "$line" | grep -q "agent-pki" || fail "chain does not name agent-pki: $line"
echo "$line" | grep -q "agent-client" || fail "chain is NOT NESTED — agent-client missing: $line"
echo "OK: full two-hop chain after consent, chain nested agent-pki <- agent-client"

echo
echo "== 5. hygiene =="
grep -hqE "$JWT_RE" "$WORK/refused.txt" "$WORK/stream.txt" \
  && fail "a token-shaped string reached the browser" || true
echo "OK: nothing token-shaped crossed the stream"

echo
echo "M15-CONSENT PASS"
