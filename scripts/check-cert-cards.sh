#!/usr/bin/env bash
# Identity cards exit criterion (demo track, after P6/D-036):
#   the console can show, as decoded certificate cards under the step that
#   produces each, (a) the agent's X.509-SVID with its chain, (b) the agent's
#   JWT-SVID as decoded claims only, (c) the certificate the MCP server
#   presented in the mTLS handshake, (d) the issued employee certificate with
#   its chain. Display only: no endpoint returns a token, a key, or (for SVIDs)
#   PEM — the P6 rule for /api/svid is unchanged and re-asserted here.
#   1. /api/svid      — unchanged shape (no breaking change for the console)
#   2. /api/jwt-svid  — header + claims + signature:"REDACTED", never the token
#   3. /api/peer      — the chain mcp-server presented, accepted only because
#                       its SPIFFE ID is the one this agent expects
#   4. /api/issued    — carries "chain" when a certificate exists (204 before)
#   5. console        — scripts/check-console.sh (lint, tests, build, offline)
set -euo pipefail
cd "$(dirname "$0")/.."
fail() { echo "CERT-CARDS FAIL: $1"; exit 1; }
WEB=http://localhost:8090
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
JWT_SHAPE='[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}'

(cd infra && docker compose --profile demo up -d --wait --wait-timeout 300) >/dev/null || fail "stack"

# ---- 1. /api/svid unchanged ------------------------------------------------
curl -s "$WEB/api/svid" > "$WORK/svid.json"
grep -q '"spiffeId":"spiffe://ai-agent.id.eviden.internal/agent-client"' "$WORK/svid.json" \
  || fail "/api/svid does not name the agent's SPIFFE ID"
grep -q '"role":"leaf"' "$WORK/svid.json" && grep -q '"signatureAlgorithm"' "$WORK/svid.json" \
  || fail "/api/svid lost leaf/details (breaking change)"
grep -qi 'PRIVATE KEY\|BEGIN CERTIFICATE' "$WORK/svid.json" && fail "/api/svid leaks key/PEM" || true
echo "OK: /api/svid unchanged"

# ---- 2. /api/jwt-svid: decoded, redacted, never the token ------------------
code=$(curl -s -o "$WORK/jwt.json" -w '%{http_code}' "$WEB/api/jwt-svid")
[ "$code" = 200 ] || fail "/api/jwt-svid HTTP $code"
grep -q '"signature":"REDACTED"' "$WORK/jwt.json" || fail "/api/jwt-svid signature not redacted"
grep -q '"sub":"spiffe://ai-agent.id.eviden.internal/agent-client"' "$WORK/jwt.json" \
  || fail "/api/jwt-svid sub is not the agent's SPIFFE ID"
grep -q 'http://keycloak:8080/realms/ai-agents' "$WORK/jwt.json" \
  || fail "/api/jwt-svid aud is not the AS issuer identifier (CLAUDE.md §3)"
grep -q '"alg"' "$WORK/jwt.json" || fail "/api/jwt-svid carries no header"
grep -qE "$JWT_SHAPE" "$WORK/jwt.json" && fail "/api/jwt-svid contains a JWT-shaped string" || true
echo "OK: /api/jwt-svid decoded claims only, aud = issuer, no token"

# ---- 3. /api/peer: what mcp-server presented ------------------------------
code=$(curl -s -o "$WORK/peer.json" -w '%{http_code}' "$WEB/api/peer?target=mcp-server")
[ "$code" = 200 ] || fail "/api/peer HTTP $code"
grep -q '"spiffeId":"spiffe://ai-agent.id.eviden.internal/mcp-server"' "$WORK/peer.json" \
  || fail "/api/peer does not name mcp-server"
grep -q '"role":"leaf"' "$WORK/peer.json" && grep -q '"role":"trust-anchor"' "$WORK/peer.json" \
  || fail "/api/peer chain lacks leaf or trust anchor"
grep -q 'URI:spiffe://ai-agent.id.eviden.internal/mcp-server' "$WORK/peer.json" \
  || fail "/api/peer leaf lacks the mcp-server URI SAN"
grep -qi 'PRIVATE KEY\|BEGIN CERTIFICATE' "$WORK/peer.json" && fail "/api/peer leaks key/PEM" || true
code=$(curl -s -o /dev/null -w '%{http_code}' "$WEB/api/peer?target=nope")
[ "$code" = 400 ] || fail "/api/peer with an unknown target expected 400, got $code"
echo "OK: /api/peer serves mcp-server's presented chain (metadata only); unknown target refused"

# ---- 4. /api/issued: chain travels with the certificate --------------------
code=$(curl -s -o "$WORK/issued.json" -w '%{http_code}' "$WEB/api/issued")
case "$code" in
  204) echo "OK: /api/issued 204 (no issuance in this session yet — chain asserted after check-m12)";;
  200) grep -q '"pem"' "$WORK/issued.json" || fail "/api/issued lost pem (breaking change)"
       grep -q '"chain":\[' "$WORK/issued.json" || fail "/api/issued carries no chain"
       grep -q '"role":"trust-anchor"' "$WORK/issued.json" || fail "/api/issued chain has no trust anchor"
       echo "OK: /api/issued carries the certificate and its chain";;
  *) fail "/api/issued HTTP $code";;
esac

# ---- 5. console -------------------------------------------------------------
bash scripts/check-console.sh || fail "console exit check"
grep -q 'JWT-SVID' console/dist/console/browser/*.js || fail "the JWT-SVID card is not in the bundle"
grep -q 'Server certificate' console/dist/console/browser/*.js || fail "the server certificate card is not in the bundle"
echo "CERT-CARDS PASS"
