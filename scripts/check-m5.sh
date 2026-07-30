#!/usr/bin/env bash
# M5 exit criterion (BUILD-PLAN M5):
#   MCP server accepts a call from the allowlisted SPIFFE ID over mTLS, and
#   rejects a valid-token call from a workload whose SPIFFE ID is not allowlisted.
# Enforcement split (ARCHITECTURE): handshake = valid lab.internal SVID required;
# app filter = allowlist -> 403. Plus: no-client-cert connection is refused.
set -euo pipefail
cd "$(dirname "$0")/.."
dkr() { MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker "$@"; }
fail() { echo "M5 FAIL: $1"; exit 1; }

KC=http://localhost:8080
NET=spiffe-mcp-lab_lab
SOCK_VOL=spiffe-mcp-lab_spire-agent-socket
IMG=spiffe-mcp-lab-agent-client
URL=https://mcp.lab.internal:8443/api/whoami

# Order matters: registration entries must exist before mcp-server starts,
# because its X509Source blocks on SVID availability at boot.
(cd infra && docker compose up -d --wait spire-server spire-agent keycloak) >/dev/null || fail "core stack not healthy"
bash infra/spire/register-workloads.sh >/dev/null
bash infra/keycloak/setup-realm.sh >/dev/null
(cd infra && docker compose up -d --wait --wait-timeout 240) >/dev/null || fail "mcp-server not healthy"

TOKEN=$(curl -s -d grant_type=password -d client_id=test-caller -d username=alice -d password=alice-password \
  "$KC/realms/lab/protocol/openid-connect/token" | sed 's/.*"access_token":"\([^"]*\)".*/\1/')
[ -n "$TOKEN" ] && [ "${#TOKEN}" -gt 100 ] || fail "could not obtain user token"

call() { # $1=workload label; runs agent-client image attested as that workload
  dkr run --rm --label org.lab.workload="$1" --network "$NET" \
    -v "$SOCK_VOL":/tmp/spire-agent/public:ro \
    -e SPIFFE_ENDPOINT_SOCKET=unix:/tmp/spire-agent/public/api.sock \
    -e TOKEN="$TOKEN" "$IMG" "$URL"
}

# -- 1. Allowlisted workload over mTLS -> 200 ------------------------------
out=$(call agent-client) || fail "allowlisted call errored: $out"
echo "$out" | grep -q "^HTTP 200" || fail "allowlisted call: want HTTP 200, got: $out"
echo "$out" | grep -q '"sub"' || fail "whoami body missing sub: $out"
echo "OK: allowlisted agent-client SVID -> 200 over mTLS"

# -- 2. Valid token, NON-allowlisted SPIFFE ID -> 403 ----------------------
out=$(call mcp-server) || true
echo "$out" | grep -q "^HTTP 403" || fail "unlisted workload: want HTTP 403, got: $out"
echo "OK: unlisted SPIFFE ID (mcp-server's own) -> 403 despite valid token"

# -- 3. No client certificate -> connection refused at handshake -----------
if curl -sk --max-time 10 -H "Authorization: Bearer $TOKEN" "https://localhost:8443/api/whoami" -o /dev/null 2>/dev/null; then
  fail "call WITHOUT client certificate was not rejected"
fi
echo "OK: no client cert -> TLS handshake rejected"

echo "M5 PASS"
