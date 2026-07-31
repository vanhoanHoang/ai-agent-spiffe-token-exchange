#!/usr/bin/env bash
# M6 exit criterion (BUILD-PLAN M6): agent-client obtains a token from Keycloak
# using ONLY its JWT-SVID as client credential. No client secret exists for it.
# Negative: the same client called by a workload whose JWT-SVID sub is a
# different SPIFFE ID is rejected (sub must map to the registered client, §3.1).
set -euo pipefail
cd "$(dirname "$0")/.."
dkr() { MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker "$@"; }
fail() { echo "M6 FAIL: $1"; exit 1; }

NET=spiffe-mcp-lab_lab
SOCK_VOL=spiffe-mcp-lab_spire-agent-socket
IMG=spiffe-mcp-lab-agent-client
TOKEN_EP=http://keycloak:8080/realms/ai-agents/protocol/openid-connect/token

bash infra/pki/issue-bundle-endpoint-cert.sh >/dev/null
(cd infra && docker compose up -d --wait spire-server spire-agent keycloak) >/dev/null || fail "core stack not healthy"
bash infra/spire/register-workloads.sh >/dev/null
bash infra/keycloak/setup-realm.sh >/dev/null
bash infra/keycloak/setup-spiffe-idp.sh || fail "spiffe idp setup failed"
(cd infra && docker compose up -d --wait --wait-timeout 240) >/dev/null || fail "stack not healthy"

token_call() { # $1=workload label — the Workload API mints for the caller's own identity
  dkr run --rm --label org.lab.workload="$1" --network "$NET" \
    -v "$SOCK_VOL":/tmp/spire-agent/public:ro \
    -e SPIFFE_ENDPOINT_SOCKET=unix:/tmp/spire-agent/public/api.sock \
    "$IMG" token "$TOKEN_EP" 2>&1
}

# -- 1. JWT-SVID as the sole client credential -> token --------------------
out=$(token_call agent-client) || fail "token call errored: $out"
echo "$out" | grep -q "^HTTP 200" || fail "want HTTP 200, got: $out"
echo "$out" | grep -q '"access_token"' || fail "no access_token in: $out"
ACCESS=$(echo "$out" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
payload=$(echo "$ACCESS" | cut -d. -f2 | tr '_-' '/+' | { p=$(cat); pad=$(( (4 - ${#p} % 4) % 4 )); printf '%s' "$p"; printf '=%.0s' $(seq 1 $pad) 2>/dev/null; } | openssl base64 -d -A 2>/dev/null)
echo "$payload" | grep -q '"azp":"agent-client"' || fail "token azp is not agent-client: $payload"
echo "OK: token issued via jwt-spiffe client assertion (azp=agent-client)"

# -- 2. No usable client secret for agent-client ---------------------------
# No secret lives in this repo/env. Keycloak auto-generates an internal secret
# row for confidential clients — prove it is NOT an accepted credential: fetch
# the generated value as admin and attempt client_secret auth with it.
grep -rqi --exclude=check-m6.sh "agent-client-secret\|AGENT_CLIENT_SECRET" infra agent-client mcp-server scripts && fail "client secret artifacts found in repo"
kc() { (cd infra && MSYS_NO_PATHCONV=1 docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh "$@"); }
kc config credentials --server http://localhost:8080 --realm master --user admin --password admin >/dev/null 2>&1
CID=$(kc get clients -r ai-agents -q clientId=agent-client --fields id 2>/dev/null | tr -d ' \n' | sed 's/.*"id":"\([^"]*\)".*/\1/')
GEN_SECRET=$(kc get "clients/$CID/client-secret" -r ai-agents 2>/dev/null | tr -d ' \n' | sed 's/.*"value":"\([^"]*\)".*/\1/')
code=$(curl -s -o /dev/null -w '%{http_code}' -d grant_type=client_credentials -d client_id=agent-client \
  -d "client_secret=$GEN_SECRET" "http://localhost:8080/realms/ai-agents/protocol/openid-connect/token")
[ "$code" = "400" ] || [ "$code" = "401" ] || fail "Keycloak's auto-generated secret AUTHENTICATED (got $code) — jwt-spiffe is not the only credential"
echo "OK: no secret in repo; Keycloak's auto-generated secret row does NOT authenticate ($code)"

# -- 3. Negative: JWT-SVID of a DIFFERENT workload -> rejected -------------
out=$(token_call mcp-server) || true
echo "$out" | grep -qE "^HTTP (400|401)" || fail "wrong-sub call: want 400/401, got: $out"
echo "OK: JWT-SVID with sub=mcp-server rejected for client agent-client"

echo "M6 PASS"
