#!/usr/bin/env bash
# M13 exit criterion: the table is law.
#
#   1. The hop-2 token carries the NESTED act chain, decoded directly from the
#      token (M12 proved it via cert-service's log; this proves the claim shape).
#   2. Off-table AUDIENCE is refused: agent-client may delegate to agent-pki
#      and nowhere else.
#   3. Off-table SCOPE is refused at the TABLE layer: agent-pki may not carry
#      onboard:initiate even though alice's token carries it (the intersection
#      executor would allow it — only the table forbids it).
#   4. DEPTH is law: no token produced by the chain can be exchanged further,
#      by either actor. Depth comes from the act chain only the AS writes.
#
# Every refusal must be the delegation-table executor speaking ("Delegation
# refused"), not a generic Keycloak error — otherwise the table is decoration.
set -uo pipefail
cd "$(dirname "$0")/.."
dkr() { MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker "$@"; }
fail() { echo "M13 FAIL: $1"; exit 1; }

KC=http://localhost:8080
NET=spiffe-mcp-lab_lab
SOCK_VOL=spiffe-mcp-lab_spire-agent-socket
IMG=spiffe-mcp-lab-agent-client
TOKEN_EP="$KC/realms/ai-agents/protocol/openid-connect/token"
ISS=http://keycloak:8080/realms/ai-agents
URN="urn:ietf:params:oauth:client-assertion-type:jwt-spiffe"
TD=spiffe://ai-agent.id.eviden.internal
XCH=urn:ietf:params:oauth:grant-type:token-exchange
ATT=urn:ietf:params:oauth:token-type:access_token

PY=python3; command -v python3 >/dev/null 2>&1 || PY=python
command -v "$PY" >/dev/null 2>&1 || fail "python3/python required for JSON claim assertions"

decode() { echo "$1" | cut -d. -f2 | tr '_-' '/+' | { p=$(cat); pad=$(( (4 - ${#p} % 4) % 4 )); printf '%s' "$p"; [ $pad -gt 0 ] && printf '=%.0s' $(seq 1 $pad); } | openssl base64 -d -A 2>/dev/null; }

# Fetch a JWT-SVID as a given workload (docker attestor selects on the label).
svid_as() { # $1 = workload label
  dkr run --rm --label "org.lab.workload=$1" --network "$NET" \
    -v "$SOCK_VOL":/tmp/spire-agent/public:ro \
    -e SPIFFE_ENDPOINT_SOCKET=unix:/tmp/spire-agent/public/api.sock \
    "$IMG" svid "$ISS" 2>/dev/null | grep -o 'ey[A-Za-z0-9._-]*' | head -1 | tr -d '\r\n'
}

exchange() { # $1 client spiffe path, $2 svid, $3 subject token, $4 scope, extra curl args...
  local client="$TD/$1" svid="$2" subject="$3" scope="$4"; shift 4
  curl -s -d grant_type="$XCH" \
    -d subject_token="$subject" -d subject_token_type="$ATT" \
    --data-urlencode client_id="$client" --data-urlencode client_assertion_type="$URN" \
    --data-urlencode client_assertion="$svid" ${scope:+-d scope="$scope"} "$@" "$TOKEN_EP"
}

token_of() { echo "$1" | grep -o '"access_token":"[^"]*"' | head -1 | cut -d'"' -f4; }

refused_by_table() { # $1 = response, $2 = expected message fragment
  echo "$1" | grep -o '"access_token"' >/dev/null && return 1
  echo "$1" | grep -q "Delegation refused" || return 1
  echo "$1" | grep -q "$2"
}

echo "== setup: alice grants both scopes; both agents fetch SVIDs =="
USER_TOKEN=$(curl -s -d grant_type=password -d client_id=test-caller -d username=alice -d password=alice-password \
  -d 'scope=openid onboard:initiate issue:employee-cert' "$TOKEN_EP" \
  | grep -o '"access_token":"[^"]*"' | head -1 | cut -d'"' -f4)
[ ${#USER_TOKEN} -gt 100 ] || fail "no user token"
ALICE_SUB=$(decode "$USER_TOKEN" | grep -o '"sub":"[^"]*"' | head -1 | cut -d'"' -f4)
CLIENT_SVID=$(svid_as agent-client); [ ${#CLIENT_SVID} -gt 100 ] || fail "no SVID for agent-client"
PKI_SVID=$(svid_as agent-pki);       [ ${#PKI_SVID} -gt 100 ] || fail "no SVID for agent-pki"
echo "OK: alice sub=$ALICE_SUB, both agents attested"

echo
echo "== 1. the hop-2 token carries the NESTED act chain =="
HOP1=$(exchange agent-client "$CLIENT_SVID" "$USER_TOKEN" "onboard:initiate")
HOP1_TOKEN=$(token_of "$HOP1"); [ ${#HOP1_TOKEN} -gt 100 ] || fail "hop 1 refused: $HOP1"
HOP2=$(exchange agent-pki "$PKI_SVID" "$HOP1_TOKEN" "issue:employee-cert")
HOP2_TOKEN=$(token_of "$HOP2"); [ ${#HOP2_TOKEN} -gt 100 ] || fail "hop 2 refused: $HOP2"
# decode ends in a guarded printf whose false branch would fail the pipeline
# under pipefail — capture first, then feed python.
HOP2_PAYLOAD=$(decode "$HOP2_TOKEN")
printf '%s' "$HOP2_PAYLOAD" | "$PY" -c '
import json, sys
td = "spiffe://ai-agent.id.eviden.internal"
t = json.load(sys.stdin)
assert t["sub"] == sys.argv[1], f"human lost: sub={t['sub']}"
act = t.get("act")
assert isinstance(act, dict) and act.get("sub") == td + "/agent-pki", f"outer act wrong: {act}"
inner = act.get("act")
assert isinstance(inner, dict) and inner.get("sub") == td + "/agent-client", f"act chain NOT NESTED: {act}"
assert inner.get("act") is None, f"chain deeper than reality: {act}"
aud = t["aud"] if isinstance(t["aud"], list) else [t["aud"]]
assert "https://cert.ai-agent.id.eviden.internal:8444" in aud, f"aud misses cert-service: {aud}"
scopes = t.get("scope", "").split()
assert "issue:employee-cert" in scopes, f"scope misses issue:employee-cert: {scopes}"
assert "onboard:initiate" not in scopes, f"hop 2 still carries hop-1 scope: {scopes}"
print("OK: act = agent-pki{act = agent-client}, sub = alice, aud = cert-service, scope attenuated to issuing")
' "$ALICE_SUB" || fail "hop-2 claim assertions failed"

echo
echo "== 2. off-table AUDIENCE refused: agent-client -> cert-service =="
R=$(exchange agent-client "$CLIENT_SVID" "$USER_TOKEN" "onboard:initiate" -d audience=cert-service)
refused_by_table "$R" "may not delegate to cert-service" \
  || fail "off-table audience was not refused by the table: $(echo "$R" | head -c 300)"
echo "OK: refused ($(echo "$R" | grep -o '"error_description":"[^"]*"'))"

echo
echo "== 3. off-table SCOPE refused at the TABLE layer: agent-pki + onboard:initiate =="
# alice consented onboard:initiate and the hop-1 token's ceiling carries it, so
# the intersection executor alone would wave this through. Only the table row
# (agent-pki: issue:employee-cert) forbids it — this isolates the table.
R=$(exchange agent-pki "$PKI_SVID" "$HOP1_TOKEN" "onboard:initiate")
refused_by_table "$R" "may not carry onboard:initiate" \
  || fail "off-table scope was not refused by the table: $(echo "$R" | head -c 300)"
echo "OK: refused ($(echo "$R" | grep -o '"error_description":"[^"]*"'))"

echo
echo "== 4. DEPTH is law: nothing the chain produced can be exchanged further =="
R=$(exchange agent-pki "$PKI_SVID" "$HOP2_TOKEN" "issue:employee-cert")
refused_by_table "$R" "depth 3 exceeds the limit of 2" \
  || fail "hop-3 attempt by agent-pki was not depth-refused: $(echo "$R" | head -c 300)"
echo "OK: agent-pki hop-3 refused"
R=$(exchange agent-client "$CLIENT_SVID" "$HOP1_TOKEN" "onboard:initiate")
refused_by_table "$R" "depth 2 exceeds the limit of 1" \
  || fail "re-exchange by agent-client was not depth-refused: $(echo "$R" | head -c 300)"
echo "OK: agent-client re-exchange refused"

echo
echo "M13 PASS"
