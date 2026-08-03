#!/usr/bin/env bash
# M12 exit criterion: the second hop exists and is REQUIRED.
#
#   1. Alice grants both task scopes. The assistant reaches the PKI agent with
#      a token that says sub=alice, act.sub=agent-client, aud=agent-pki.
#   2. The PKI agent exchanges again and calls the certificate service. The
#      certificate service sees a NESTED act chain: agent-pki acting for
#      agent-client acting for alice.
#   3. The assistant CANNOT reach the certificate service directly. Not
#      "should not" — its SPIFFE ID is not allowlisted there and its token's
#      audience is wrong.
#   4. Neither agent holds the other's scope, so neither can finish alone.
set -uo pipefail
cd "$(dirname "$0")/.."
dkr() { MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker "$@"; }
fail() { echo "M12 FAIL: $1"; exit 1; }

KC=http://localhost:8080
NET=spiffe-mcp-lab_lab
SOCK_VOL=spiffe-mcp-lab_spire-agent-socket
IMG=spiffe-mcp-lab-agent-client
TOKEN_EP="$KC/realms/ai-agents/protocol/openid-connect/token"
ISS=http://keycloak:8080/realms/ai-agents
PKI_EP=https://pki-agent.ai-agent.id.eviden.internal:8445/mcp
CERT_EP=https://cert.ai-agent.id.eviden.internal:8444/mcp
URN="urn:ietf:params:oauth:client-assertion-type:jwt-spiffe"
AGENT_ID="spiffe://ai-agent.id.eviden.internal/agent-client"

decode() { echo "$1" | cut -d. -f2 | tr '_-' '/+' | { p=$(cat); pad=$(( (4 - ${#p} % 4) % 4 )); printf '%s' "$p"; [ $pad -gt 0 ] && printf '=%.0s' $(seq 1 $pad); } | openssl base64 -d -A 2>/dev/null; }

# PEER_SPIFFE_ID names which server the probe will accept. It stays an explicit
# accepted-ID check throughout; the hops simply trust different peers.
as_agent() { dkr run --rm --label org.lab.workload=agent-client --network "$NET" \
    -v "$SOCK_VOL":/tmp/spire-agent/public:ro \
    -e SPIFFE_ENDPOINT_SOCKET=unix:/tmp/spire-agent/public/api.sock \
    ${TOKEN:+-e TOKEN="$TOKEN"} ${PEER_SPIFFE_ID:+-e PEER_SPIFFE_ID="$PEER_SPIFFE_ID"} \
    ${TOOL_ARGS:+-e TOOL_ARGS="$TOOL_ARGS"} "$IMG" "$@" 2>&1; }

echo "== alice signs in and grants both task scopes =="
USER_TOKEN=$(curl -s -d grant_type=password -d client_id=test-caller -d username=alice -d password=alice-password \
  -d 'scope=openid onboard:initiate issue:employee-cert' "$TOKEN_EP" \
  | grep -o '"access_token":"[^"]*"' | head -1 | cut -d'"' -f4)
[ ${#USER_TOKEN} -gt 100 ] || fail "no user token"
ALICE_SUB=$(decode "$USER_TOKEN" | grep -o '"sub":"[^"]*"' | head -1 | cut -d'"' -f4)
decode "$USER_TOKEN" | grep -q "onboard:initiate" || fail "alice's token lacks onboard:initiate"
echo "OK: alice granted onboard:initiate and issue:employee-cert (sub=$ALICE_SUB)"

echo
echo "== hop 1: the assistant exchanges for the PKI agent =="
SVID=$(TOKEN= PEER_SPIFFE_ID= as_agent svid "$ISS" | grep -o 'ey[A-Za-z0-9._-]*' | head -1 | tr -d '\r\n')
[ ${#SVID} -gt 100 ] || fail "no JWT-SVID for agent-client"
HOP1=$(curl -s -d grant_type=urn:ietf:params:oauth:grant-type:token-exchange \
  -d subject_token="$USER_TOKEN" -d subject_token_type=urn:ietf:params:oauth:token-type:access_token \
  --data-urlencode client_id="$AGENT_ID" --data-urlencode client_assertion_type="$URN" \
  --data-urlencode client_assertion="$SVID" -d scope="onboard:initiate" "$TOKEN_EP")
HOP1_TOKEN=$(echo "$HOP1" | grep -o '"access_token":"[^"]*"' | head -1 | cut -d'"' -f4)
[ ${#HOP1_TOKEN} -gt 100 ] || fail "hop 1 exchange refused: $HOP1"
P1=$(decode "$HOP1_TOKEN")
echo "$P1" | grep -q "\"sub\":\"$ALICE_SUB\"" || fail "hop 1 lost the human: $P1"
echo "$P1" | grep -q "agent-client" || fail "hop 1 has no act.sub for the assistant: $P1"
# The exercisable permission is the "scope" claim (what resource servers enforce).
# "del_scope" is the consent ceiling and legitimately carries the issuing scope —
# so the no-issuing-power assertion must read the scope claim alone, not the payload.
P1_SCOPE=$(echo "$P1" | grep -o '[,{]"scope":"[^"]*"')
echo "$P1_SCOPE" | grep -q "onboard:initiate" || fail "hop 1 scope lacks onboard:initiate: $P1"
echo "$P1_SCOPE" | grep -q "issue:employee-cert" && fail "hop 1 token carries the ISSUING scope — the hop would be pointless: $P1_SCOPE"
echo "OK: hop 1 token is sub=alice, act=agent-client, scope=onboard:initiate, no issuing power"

echo
echo "== hop 2 + issuance: the assistant asks the PKI agent to onboard =="
out=$(TOKEN="$HOP1_TOKEN" PEER_SPIFFE_ID="spiffe://ai-agent.id.eviden.internal/agent-pki" TOOL_ARGS='{"device":"john-laptop"}' as_agent mcp "$PKI_EP" tools/call onboard_employee)
echo "$out" | grep -q "^HTTP 200" || fail "onboarding call failed: $(echo "$out" | head -5)"
echo "$out" | grep -qi '"isError":true' && fail "onboarding returned an error: $(echo "$out" | head -8)"
echo "$out" | grep -q "issued" || fail "no issuance in the response: $(echo "$out" | head -8)"
echo "OK: the chain completed and a certificate came back"

echo
echo "== the certificate service saw the FULL chain =="
logs=$(dkr logs --tail 200 spiffe-mcp-lab-cert-service-1 2>&1)
echo "$logs" | grep -q "ISSUED" || fail "cert-service logged no issuance"
echo "$logs" | grep "ISSUED" | tail -1 | grep -q "$ALICE_SUB" \
  || fail "cert-service did not record alice as the human: $(echo "$logs" | grep ISSUED | tail -1)"
echo "$logs" | grep "ISSUED" | tail -1 | grep -q "agent-pki" \
  || fail "chain does not name agent-pki: $(echo "$logs" | grep ISSUED | tail -1)"
echo "$logs" | grep "ISSUED" | tail -1 | grep -q "agent-client" \
  || fail "chain is NOT NESTED — agent-client missing: $(echo "$logs" | grep ISSUED | tail -1)"
echo "OK: cert-service logged sub=alice with the nested chain agent-pki <- agent-client"

echo
echo "== the assistant cannot reach the certificate service directly =="
out=$(TOKEN="$HOP1_TOKEN" PEER_SPIFFE_ID="spiffe://ai-agent.id.eviden.internal/cert-service" TOOL_ARGS='{"subject":"direct-attempt"}' as_agent mcp "$CERT_EP" tools/call issue_employee_cert)
echo "$out" | grep -q "^HTTP 200" && fail "ASSISTANT REACHED THE CERTIFICATE SERVICE: $(echo "$out" | head -5)"
echo "OK: refused ($(echo "$out" | head -1))"

echo
echo "== neither agent can finish alone =="
ESC=$(curl -s -d grant_type=urn:ietf:params:oauth:grant-type:token-exchange \
  -d subject_token="$USER_TOKEN" -d subject_token_type=urn:ietf:params:oauth:token-type:access_token \
  --data-urlencode client_id="$AGENT_ID" --data-urlencode client_assertion_type="$URN" \
  --data-urlencode client_assertion="$SVID" -d scope="issue:employee-cert" "$TOKEN_EP")
echo "$ESC" | grep -o '"access_token":"[^"]*"' >/dev/null 2>&1 \
  && fail "the assistant obtained issue:employee-cert — one agent can do everything"
echo "OK: the assistant cannot obtain the issuing scope ($(echo "$ESC" | head -c 120))"

echo
echo "M12 PASS"
