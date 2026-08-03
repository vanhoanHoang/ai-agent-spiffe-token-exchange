#!/usr/bin/env bash
# Exit criterion for the D-030 finding-3 fix: CLAUDE.md §2's intersection
#   effective permissions = user scopes ∩ agent allowed scopes
# is ENFORCED, in both directions, at the authorization server.
#
#   1. POSITIVE  alice consents to mcp:audit -> the exchanged token CARRIES it
#                (the consent toggle is load-bearing, not decorative).
#   2. NEGATIVE  alice does NOT consent -> the agent requests mcp:audit anyway
#                -> the exchange is REFUSED (not silently granted).
#   3. NEGATIVE  end-to-end: no token obtainable without consent lets the
#                scope-gated MCP tool run.
#   4. Regression: the default path (no scope requested) still works.
#
# Both directions are asserted deliberately: this bug shipped because only the
# refusal was ever checked.
set -uo pipefail
cd "$(dirname "$0")/.."
dkr() { MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker "$@"; }
fail() { echo "SCOPE-INTERSECTION FAIL: $1"; exit 1; }

KC=http://localhost:8080
NET=spiffe-mcp-lab_lab
SOCK_VOL=spiffe-mcp-lab_spire-agent-socket
IMG=spiffe-mcp-lab-agent-client
MCP_EP=https://mcp.ai-agent.id.eviden.internal:8443/mcp
ISS=http://keycloak:8080/realms/ai-agents
TOKEN_EP="$KC/realms/ai-agents/protocol/openid-connect/token"
URN="urn:ietf:params:oauth:client-assertion-type:jwt-spiffe"
SPIFFE_ID="spiffe://ai-agent.id.eviden.internal/agent-client"

decode() { echo "$1" | cut -d. -f2 | tr '_-' '/+' | { p=$(cat); pad=$(( (4 - ${#p} % 4) % 4 )); printf '%s' "$p"; [ $pad -gt 0 ] && printf '=%.0s' $(seq 1 $pad); } | openssl base64 -d -A 2>/dev/null; }
scope_of() { decode "$1" | grep -o '"scope":"[^"]*"' | cut -d'"' -f4; }

user_token() { # $1 = scope request (may be empty)
  curl -s -d grant_type=password -d client_id=test-caller -d username=alice -d password=alice-password \
    ${1:+-d "scope=$1"} "$TOKEN_EP" | grep -o '"access_token":"[^"]*"' | head -1 | cut -d'"' -f4
}

in_agent() { dkr run --rm --label org.lab.workload=agent-client --network "$NET" \
    -v "$SOCK_VOL":/tmp/spire-agent/public:ro \
    -e SPIFFE_ENDPOINT_SOCKET=unix:/tmp/spire-agent/public/api.sock \
    ${TOKEN:+-e TOKEN="$TOKEN"} ${SUBJECT_TOKEN:+-e SUBJECT_TOKEN="$SUBJECT_TOKEN"} \
    "$IMG" "$@" 2>/dev/null; }

# Raw exchange with an explicit scope parameter — this is the shape a
# COMPROMISED agent would send, so it must be refused by the server, not by
# client-side politeness.
raw_exchange() { # $1 = subject token, $2 = scope (may be empty)
  local svid; svid=$(TOKEN= SUBJECT_TOKEN= in_agent svid "$ISS" | tr -d '\r\n')
  [ ${#svid} -gt 100 ] || { echo "NO_SVID"; return; }
  curl -s -d grant_type=urn:ietf:params:oauth:grant-type:token-exchange \
    -d subject_token="$1" -d subject_token_type=urn:ietf:params:oauth:token-type:access_token \
    --data-urlencode client_id="$SPIFFE_ID" --data-urlencode client_assertion_type="$URN" \
    --data-urlencode client_assertion="$svid" ${2:+-d "scope=$2"} "$TOKEN_EP"
}

echo "== preconditions =="
TOK_CONSENTED=$(user_token "openid mcp:audit")
TOK_PLAIN=$(user_token "")
[ ${#TOK_CONSENTED} -gt 100 ] || fail "no consented user token"
[ ${#TOK_PLAIN} -gt 100 ] || fail "no plain user token"
echo "$(scope_of "$TOK_CONSENTED")" | grep -q "mcp:audit" || fail "consented token lacks mcp:audit — fixture broken"
echo "$(scope_of "$TOK_PLAIN")" | grep -q "mcp:audit" && fail "plain token HAS mcp:audit — fixture broken"
echo "OK: fixtures real (consented token has mcp:audit, plain token does not)"

echo
echo "== 1. POSITIVE: consent must reach the exchanged token =="
res=$(raw_exchange "$TOK_CONSENTED" "mcp:audit")
EX_CONSENTED=$(echo "$res" | grep -o '"access_token":"[^"]*"' | head -1 | cut -d'"' -f4)
[ ${#EX_CONSENTED} -gt 100 ] || fail "consented exchange refused — the grant must be honored: $res"
echo "$(scope_of "$EX_CONSENTED")" | grep -q "mcp:audit" \
  || fail "consented exchange dropped mcp:audit (scope=$(scope_of "$EX_CONSENTED")) — consent toggle is decorative"
echo "OK: alice's consent survives the exchange (scope=$(scope_of "$EX_CONSENTED"))"

TOKEN="$EX_CONSENTED" SUBJECT_TOKEN= out=$(TOKEN="$EX_CONSENTED" SUBJECT_TOKEN= in_agent mcp "$MCP_EP" tools/call read_audit_log)
echo "$out" | grep -qi "insufficient_scope" \
  && fail "consented token was REFUSED at the MCP server — the positive path is still dead"
echo "$out" | grep -q '"isError":false' || fail "consented audit read did not succeed: $(echo "$out" | head -3)"
echo "OK: with consent, the scope-gated tool runs"

echo
echo "== 2. NEGATIVE: escalation beyond alice's grant must be REFUSED =="
res=$(raw_exchange "$TOK_PLAIN" "mcp:audit")
EX_ESC=$(echo "$res" | grep -o '"access_token":"[^"]*"' | head -1 | cut -d'"' -f4)
if [ ${#EX_ESC} -gt 100 ]; then
  echo "$(scope_of "$EX_ESC")" | grep -q "mcp:audit" \
    && fail "ESCALATION: exchanged token carries mcp:audit alice never granted (scope=$(scope_of "$EX_ESC"))"
  echo "OK: exchange succeeded but stripped the ungranted scope (scope=$(scope_of "$EX_ESC"))"
else
  echo "$res" | grep -qi "invalid_scope\|access_denied\|invalid_request" \
    || fail "exchange failed for an unexpected reason: $res"
  echo "OK: exchange refused the ungranted scope"
fi

echo
echo "== 3. NEGATIVE end-to-end: no consent, no audit read =="
if [ ${#EX_ESC} -gt 100 ]; then
  out=$(TOKEN="$EX_ESC" SUBJECT_TOKEN= in_agent mcp "$MCP_EP" tools/call read_audit_log)
  echo "$out" | grep -qi "insufficient_scope" \
    || fail "AUDIT LOG READ WITHOUT CONSENT: $(echo "$out" | head -5)"
  echo "OK: MCP server refuses the escalated token (insufficient_scope)"
else
  echo "OK: no token to present (refused at the AS — strictly stronger)"
fi

echo
echo "== 4. regression: the default path still works =="
res=$(raw_exchange "$TOK_PLAIN" "")
EX_DEF=$(echo "$res" | grep -o '"access_token":"[^"]*"' | head -1 | cut -d'"' -f4)
[ ${#EX_DEF} -gt 100 ] || fail "default exchange broke: $res"
echo "$(scope_of "$EX_DEF")" | grep -q "mcp:audit" && fail "default exchange leaked mcp:audit"
echo "OK: default exchange works and carries no audit scope"

out=$(TOKEN="$EX_DEF" SUBJECT_TOKEN= in_agent mcp "$MCP_EP" tools/call whoami)
echo "$out" | grep -q '"isError":false' || fail "ordinary tool call broke: $(echo "$out" | head -3)"
echo "OK: ordinary MCP tool call unaffected"

echo
echo "SCOPE-INTERSECTION PASS"
