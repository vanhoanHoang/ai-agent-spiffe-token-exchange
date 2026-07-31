#!/usr/bin/env bash
# M10 P1 exit criterion (DEMO-PLAN):
#  - MCP initialize / tools/list / tools/call succeed over SVID mTLS with the
#    exchanged token, and the server logs sub + act (chain of custody survives
#    the protocol layer).
#  - The scope-gated tool alone is refused (P3 fixture works).
#  - ./infra/acceptance.sh still exits 0, untouched.
set -euo pipefail
cd "$(dirname "$0")/.."
dkr() { MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker "$@"; }
fail() { echo "P1 FAIL: $1"; exit 1; }

KC=http://localhost:8080
NET=spiffe-mcp-lab_lab
SOCK_VOL=spiffe-mcp-lab_spire-agent-socket
IMG=spiffe-mcp-lab-agent-client
TOKEN_EP=http://keycloak:8080/realms/lab/protocol/openid-connect/token
MCP_EP=https://mcp.lab.internal:8443/mcp

bash infra/pki/issue-bundle-endpoint-cert.sh >/dev/null
(cd infra && docker compose up -d --wait spire-server spire-agent keycloak) >/dev/null || fail "core stack not healthy"
bash infra/spire/register-workloads.sh >/dev/null
bash infra/keycloak/setup-realm.sh >/dev/null
bash infra/keycloak/setup-spiffe-idp.sh >/dev/null || fail "keycloak setup failed"
(cd infra && docker compose up -d --wait --wait-timeout 240) >/dev/null || fail "stack not healthy"

USER_TOKEN=$(curl -s -d grant_type=password -d client_id=test-caller -d username=alice -d password=alice-password \
  "$KC/realms/lab/protocol/openid-connect/token" | sed 's/.*"access_token":"\([^"]*\)".*/\1/')
[ "${#USER_TOKEN}" -gt 100 ] || fail "no user token"

ac() { dkr run --rm --label org.lab.workload=agent-client --network "$NET" \
    -v "$SOCK_VOL":/tmp/spire-agent/public:ro \
    -e SPIFFE_ENDPOINT_SOCKET=unix:/tmp/spire-agent/public/api.sock \
    ${TOKEN:+-e TOKEN="$TOKEN"} ${SUBJECT_TOKEN:+-e SUBJECT_TOKEN="$SUBJECT_TOKEN"} \
    "$IMG" "$@" 2>/dev/null; }

out=$(TOKEN= SUBJECT_TOKEN="$USER_TOKEN" ac token "$TOKEN_EP")
ACCESS=$(echo "$out" | grep -o '"access_token":"[^"]*"' | head -1 | cut -d'"' -f4)
[ "${#ACCESS}" -gt 100 ] || fail "exchange failed: $out"

out=$(TOKEN="$ACCESS" SUBJECT_TOKEN= ac mcp "$MCP_EP" initialize)
echo "$out" | grep -q "^HTTP 200" || fail "initialize: $out"
echo "$out" | grep -q '"serverInfo"' || fail "initialize lacks serverInfo: $out"
echo "OK: MCP initialize over SVID mTLS"

out=$(TOKEN="$ACCESS" SUBJECT_TOKEN= ac mcp "$MCP_EP" tools/list)
for t in whoami lab_status read_audit_log; do
  echo "$out" | grep -q "\"$t\"" || fail "tools/list missing $t: $out"
done
echo "OK: tools/list advertises whoami, lab_status, read_audit_log"

out=$(TOKEN="$ACCESS" SUBJECT_TOKEN= ac mcp "$MCP_EP" tools/call whoami)
echo "$out" | grep -q "^HTTP 200" || fail "tools/call whoami: $out"
echo "$out" | grep -q "spiffe://lab.internal/agent-client" || fail "whoami lacks workload identity: $out"
echo "OK: tools/call whoami returns both identities"

out=$(TOKEN="$ACCESS" SUBJECT_TOKEN= ac mcp "$MCP_EP" tools/call read_audit_log)
echo "$out" | grep -q "insufficient_scope" || fail "scope-gated tool was NOT refused: $out"
echo "OK: scope-gated read_audit_log refused (insufficient_scope)"

(cd infra && docker compose logs mcp-server 2>/dev/null) | grep -q "tool=whoami" || fail "server did not log the tool call"
(cd infra && docker compose logs mcp-server 2>/dev/null) | grep -q "act={sub=spiffe://lab.internal/agent-client}" \
  || fail "act.sub missing from server log"
echo "OK: server logged tool call with sub + act"

bash infra/acceptance.sh >/dev/null 2>&1 || fail "acceptance.sh no longer exits 0"
echo "OK: acceptance.sh still green"
echo "P1 PASS"
