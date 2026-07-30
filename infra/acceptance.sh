#!/usr/bin/env bash
# M9 — terminal acceptance. Green here = the project is done (BUILD-PLAN M9).
#
# Happy path:  login -> jwt-spiffe token exchange -> mTLS MCP call with correct
#              sub/act/aud, act.sub logged by the server.
# Rejections:  (1) no client cert            -> refused at TLS handshake
#              (2) wrong-audience token      -> 401  (anti-passthrough, M4)
#              (3) JWT-SVID as bearer        -> 401  (forbidden pattern #1)
#              (4) unlisted SPIFFE ID        -> 403  (allowlist, M5)
#              (5) token replay by another   -> 403  (act↔peer binding, D-009 —
#                  allowlisted test-agent presenting agent-client's token)
# Chain of custody: fresh SVID chains to the EJBCA root; the intermediate's URI
#              name constraint is present+critical; act.sub appears in the log.
set -uo pipefail
cd "$(dirname "$0")/.."
dkr() { MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker "$@"; }

KC=http://localhost:8080
NET=spiffe-mcp-lab_lab
SOCK_VOL=spiffe-mcp-lab_spire-agent-socket
IMG=spiffe-mcp-lab-agent-client
TOKEN_EP=http://keycloak:8080/realms/lab/protocol/openid-connect/token
MCP_URL=https://mcp.lab.internal:8443/api/whoami
RESOURCE_ID="https://mcp.lab.internal:8443"
PKI=infra/pki

FAIL=0
say()  { printf '%-58s %s\n' "$1" "$2"; }
pass() { say "$1" "PASS"; }
flunk(){ say "$1" "FAIL${2:+ ($2)}"; FAIL=1; }

decode() { echo "$1" | cut -d. -f2 | tr '_-' '/+' | { p=$(cat); pad=$(( (4 - ${#p} % 4) % 4 )); printf '%s' "$p"; [ $pad -gt 0 ] && printf '=%.0s' $(seq 1 $pad); } | openssl base64 -d -A 2>/dev/null; }

run_ac() { # $1=workload label, rest=args; TOKEN/SUBJECT_TOKEN via env
  dkr run --rm --label org.lab.workload="$1" --network "$NET" \
    -v "$SOCK_VOL":/tmp/spire-agent/public:ro \
    -e SPIFFE_ENDPOINT_SOCKET=unix:/tmp/spire-agent/public/api.sock \
    ${TOKEN:+-e TOKEN="$TOKEN"} ${SUBJECT_TOKEN:+-e SUBJECT_TOKEN="$SUBJECT_TOKEN"} \
    "$IMG" "${@:2}" 2>/dev/null
}

# ---- Setup (idempotent) ---------------------------------------------------
bash infra/pki/setup-ejbca.sh >/dev/null || { echo "EJBCA setup failed"; exit 1; }
bash infra/pki/issue-bundle-endpoint-cert.sh >/dev/null || { echo "bundle-endpoint cert failed"; exit 1; }
(cd infra && docker compose up -d --wait spire-server spire-agent keycloak) >/dev/null || { echo "core stack failed"; exit 1; }
bash infra/spire/register-workloads.sh >/dev/null || { echo "registration failed"; exit 1; }
bash infra/keycloak/setup-realm.sh >/dev/null || { echo "realm setup failed"; exit 1; }
bash infra/keycloak/setup-spiffe-idp.sh >/dev/null || { echo "spiffe idp setup failed"; exit 1; }
(cd infra && docker compose up -d --wait --wait-timeout 240) >/dev/null || { echo "full stack failed"; exit 1; }

# ---- Happy path -----------------------------------------------------------
USER_TOKEN=$(curl -s -d grant_type=password -d client_id=test-caller -d username=alice -d password=alice-password \
  "$KC/realms/lab/protocol/openid-connect/token" | sed 's/.*"access_token":"\([^"]*\)".*/\1/')
[ "${#USER_TOKEN}" -gt 100 ] && pass "user login (password grant)" || flunk "user login"
ALICE_SUB=$(decode "$USER_TOKEN" | grep -o '"sub":"[^"]*"' | head -1 | cut -d'"' -f4)

out=$(SUBJECT_TOKEN="$USER_TOKEN" TOKEN= run_ac agent-client token "$TOKEN_EP")
ACCESS=$(echo "$out" | grep -o '"access_token":"[^"]*"' | head -1 | cut -d'"' -f4)
[ "${#ACCESS}" -gt 100 ] && pass "jwt-spiffe token exchange" || flunk "jwt-spiffe token exchange" "$out"

payload=$(decode "$ACCESS")
echo "$payload" | grep -q "\"sub\":\"$ALICE_SUB\"" \
  && echo "$payload" | grep -q '"act":{"sub":"spiffe://lab.internal/agent-client"}' \
  && echo "$payload" | grep -q "$RESOURCE_ID" \
  && pass "token claims (sub=human, act.sub=SPIFFE ID, aud=MCP)" || flunk "token claims" "$payload"

out=$(TOKEN="$ACCESS" SUBJECT_TOKEN= run_ac agent-client "$MCP_URL")
echo "$out" | grep -q "^HTTP 200" && echo "$out" | grep -q '"act"' \
  && pass "authorized MCP call over SVID mTLS" || flunk "authorized MCP call" "$out"

# ---- The five rejections (these ARE the security model) -------------------
if curl -sk --max-time 10 -H "Authorization: Bearer $ACCESS" "https://localhost:8443/api/whoami" -o /dev/null 2>/dev/null; then
  flunk "no client cert -> rejected"
else pass "no client cert -> rejected at TLS handshake"; fi

WRONG=$(curl -s -d grant_type=client_credentials -d client_id=wrong-aud-client -d client_secret=wrong-aud-secret \
  "$KC/realms/lab/protocol/openid-connect/token" | sed 's/.*"access_token":"\([^"]*\)".*/\1/')
out=$(TOKEN="$WRONG" SUBJECT_TOKEN= run_ac agent-client "$MCP_URL")
echo "$out" | grep -q "^HTTP 401" && pass "wrong-audience token -> 401" || flunk "wrong-audience token" "$out"

SVID_BEARER=$(TOKEN= SUBJECT_TOKEN= run_ac agent-client svid "$RESOURCE_ID" | tail -1)
out=$(TOKEN="$SVID_BEARER" SUBJECT_TOKEN= run_ac agent-client "$MCP_URL")
echo "$out" | grep -q "^HTTP 401" && pass "JWT-SVID as bearer -> 401" || flunk "JWT-SVID as bearer" "$out"

out=$(TOKEN="$ACCESS" SUBJECT_TOKEN= run_ac mcp-server "$MCP_URL")
echo "$out" | grep -q "^HTTP 403" && echo "$out" | grep -q "not allowlisted" \
  && pass "unlisted SPIFFE ID -> 403" || flunk "unlisted SPIFFE ID" "$out"

out=$(TOKEN="$ACCESS" SUBJECT_TOKEN= run_ac test-agent "$MCP_URL")
echo "$out" | grep -q "^HTTP 403" && echo "$out" | grep -q "actor/peer mismatch" \
  && pass "token replay by other workload -> 403 (act!=peer)" || flunk "token replay binding" "$out"

# ---- Chain of custody -----------------------------------------------------
TMP=".acc.$$"; mkdir -p "$TMP"; OUT_VOL=acc-svid-out
docker volume rm -f "$OUT_VOL" >/dev/null 2>&1
dkr run --rm --label org.lab.workload=agent-client \
  -v "$SOCK_VOL":/spire-sock:ro -v "$OUT_VOL":/out \
  --entrypoint /opt/spire/bin/spire-agent ghcr.io/spiffe/spire-agent:1.15.2 \
  api fetch x509 -socketPath /spire-sock/api.sock -write /out >/dev/null 2>&1
dkr run --rm -v "$OUT_VOL":/out:ro busybox cat /out/svid.0.pem > "$TMP/chain.pem" 2>/dev/null
dkr run --rm -v "$OUT_VOL":/out:ro busybox cat /out/bundle.0.pem > "$TMP/bundle.pem" 2>/dev/null
awk '/BEGIN CERT/{n++} n==1' "$TMP/chain.pem" > "$TMP/leaf.pem"
awk '/BEGIN CERT/{n++} n>1'  "$TMP/chain.pem" > "$TMP/rest.pem"
cat "$TMP/rest.pem" "$TMP/bundle.pem" "$PKI/chain.pem" > "$TMP/untrusted.pem"
if openssl verify -CAfile "$PKI/ejbca-root.pem" -untrusted "$TMP/untrusted.pem" "$TMP/leaf.pem" >/dev/null 2>&1 \
   && openssl x509 -in "$PKI/spire-intermediate.pem" -noout -text | grep -A2 "Name Constraints: critical" | grep -q "URI:lab.internal"; then
  pass "SVID chains to EJBCA root, constraint present+critical"
else flunk "chain of custody"; fi
rm -rf "$TMP"; docker volume rm -f "$OUT_VOL" >/dev/null 2>&1

(cd infra && docker compose logs mcp-server 2>/dev/null) | grep -q "act={sub=spiffe://lab.internal/agent-client}" \
  && pass "act.sub logged on MCP calls" || flunk "act logging"

echo
[ $FAIL -eq 0 ] && echo "ACCEPTANCE PASS — the project is done." || echo "ACCEPTANCE FAIL"
exit $FAIL
