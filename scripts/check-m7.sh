#!/usr/bin/env bash
# M7 exit criterion (BUILD-PLAN M7): decoded exchanged access token shows
# sub = human, act.sub = spiffe://ai-agent.id.eviden.internal/..., aud = MCP server; the MCP
# server logs both on every call. Plus: subject token lacking the requester in
# its aud is rejected (StandardTokenExchangeProvider rule).
set -euo pipefail
cd "$(dirname "$0")/.."
dkr() { MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker "$@"; }
fail() { echo "M7 FAIL: $1"; exit 1; }

KC=http://localhost:8080
NET=spiffe-mcp-lab_lab
SOCK_VOL=spiffe-mcp-lab_spire-agent-socket
IMG=spiffe-mcp-lab-agent-client
TOKEN_EP=http://keycloak:8080/realms/ai-agents/protocol/openid-connect/token
RESOURCE_ID="https://mcp.ai-agent.id.eviden.internal:8443"

decode() { # $1 = jwt -> payload json
  echo "$1" | cut -d. -f2 | tr '_-' '/+' | { p=$(cat); pad=$(( (4 - ${#p} % 4) % 4 )); printf '%s' "$p"; [ $pad -gt 0 ] && printf '=%.0s' $(seq 1 $pad); } | openssl base64 -d -A 2>/dev/null
}

bash infra/pki/issue-bundle-endpoint-cert.sh >/dev/null
(cd infra && docker compose up -d --wait spire-server spire-agent keycloak) >/dev/null || fail "core stack not healthy"
bash infra/spire/register-workloads.sh >/dev/null
bash infra/keycloak/setup-realm.sh >/dev/null
bash infra/keycloak/setup-spiffe-idp.sh >/dev/null || fail "spiffe idp/exchange setup failed"
(cd infra && docker compose up -d --wait --wait-timeout 240) >/dev/null || fail "stack not healthy"

# -- subject token: the human authenticates ---------------------------------
USER_TOKEN=$(curl -s -d grant_type=password -d client_id=test-caller -d username=alice -d password=alice-password \
  "$KC/realms/ai-agents/protocol/openid-connect/token" | sed 's/.*"access_token":"\([^"]*\)".*/\1/')
[ -n "$USER_TOKEN" ] && [ "${#USER_TOKEN}" -gt 100 ] || fail "could not obtain user token"
ALICE_SUB=$(decode "$USER_TOKEN" | grep -o '"sub":"[^"]*"' | head -1 | cut -d'"' -f4)
[ -n "$ALICE_SUB" ] || fail "cannot read alice sub"

# -- the agent exchanges it, authenticating with its JWT-SVID ---------------
out=$(dkr run --rm --label org.lab.workload=agent-client --network "$NET" \
  -v "$SOCK_VOL":/tmp/spire-agent/public:ro \
  -e SPIFFE_ENDPOINT_SOCKET=unix:/tmp/spire-agent/public/api.sock \
  -e SUBJECT_TOKEN="$USER_TOKEN" "$IMG" token "$TOKEN_EP" 2>&1) || fail "exchange errored: $out"
echo "$out" | grep -q "^HTTP 200" || fail "exchange: want HTTP 200, got: $out"
EXCHANGED=$(echo "$out" | grep -o '"access_token":"[^"]*"' | head -1 | cut -d'"' -f4)
payload=$(decode "$EXCHANGED")

echo "$payload" | grep -q "\"sub\":\"$ALICE_SUB\"" || fail "exchanged sub != alice: $payload"
echo "$payload" | grep -q '"act":{"sub":"spiffe://ai-agent.id.eviden.internal/agent-client"}' || fail "act.sub missing/wrong: $payload"
echo "$payload" | grep -q "$RESOURCE_ID" || fail "aud lacks $RESOURCE_ID: $payload"
echo "OK: exchanged token — sub=alice, act.sub=spiffe://ai-agent.id.eviden.internal/agent-client, aud=mcp"

# -- the exchanged token works at the MCP server over SVID mTLS -------------
out=$(dkr run --rm --label org.lab.workload=agent-client --network "$NET" \
  -v "$SOCK_VOL":/tmp/spire-agent/public:ro \
  -e SPIFFE_ENDPOINT_SOCKET=unix:/tmp/spire-agent/public/api.sock \
  -e TOKEN="$EXCHANGED" "$IMG" "https://mcp.ai-agent.id.eviden.internal:8443/api/whoami" 2>&1) || fail "mcp call errored: $out"
echo "$out" | grep -q "^HTTP 200" || fail "mcp call: want 200, got: $out"
echo "$out" | grep -q '"act":{"sub":"spiffe://ai-agent.id.eviden.internal/agent-client"}' || fail "mcp response lacks act: $out"
(cd infra && docker compose logs mcp-server 2>/dev/null | grep "call sub=" | tail -1 | grep -q "act={sub=spiffe://ai-agent.id.eviden.internal/agent-client}") \
  || fail "mcp-server log does not show act.sub"
echo "OK: MCP call 200; server logged sub + act.sub"

# -- negative: subject token without requester in aud -> rejected -----------
WRONG_SUBJ=$(curl -s -d grant_type=client_credentials -d client_id=wrong-aud-client -d client_secret=wrong-aud-secret \
  "$KC/realms/ai-agents/protocol/openid-connect/token" | sed 's/.*"access_token":"\([^"]*\)".*/\1/')
out=$(dkr run --rm --label org.lab.workload=agent-client --network "$NET" \
  -v "$SOCK_VOL":/tmp/spire-agent/public:ro \
  -e SPIFFE_ENDPOINT_SOCKET=unix:/tmp/spire-agent/public/api.sock \
  -e SUBJECT_TOKEN="$WRONG_SUBJ" "$IMG" token "$TOKEN_EP" 2>&1) || true
echo "$out" | grep -qE "^HTTP (400|403)" || fail "subject token without requester aud: want 400/403, got: $out"
echo "OK: subject token lacking requester audience rejected"

echo "M7 PASS"
