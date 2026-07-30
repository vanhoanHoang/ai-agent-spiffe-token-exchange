#!/usr/bin/env bash
# M9 — terminal acceptance test. The goal, executable.
# Green here = the project is done. Anything less is a milestone, not the goal.
set -euo pipefail

KC=http://localhost:8080/realms/lab
MCP=https://mcp.lab.internal:8443
FAIL=0
say(){ printf '%-58s %s\n' "$1" "$2"; }
need(){ [ "$1" = "$2" ] && say "$3" PASS || { say "$3" "FAIL (got $1, want $2)"; FAIL=1; }; }

# -- Happy path -----------------------------------------------------------
# 1. User token (password grant acceptable for the lab realm's test user)
USER_TOKEN=$(./scripts/get-user-token.sh)          # TODO M7
# 2. Agent: JWT-SVID from Workload API, token exchange with jwt-spiffe client auth
ACCESS=$(./scripts/agent-exchange.sh "$USER_TOKEN") # TODO M6+M7
# 3. Assert claims: sub=human, act.sub=spiffe://lab.internal/..., aud=MCP
./scripts/assert-claims.sh "$ACCESS" && say "token claims (sub/act/aud)" PASS || { say "token claims" FAIL; FAIL=1; }
# 4. mTLS + bearer call succeeds
code=$(./scripts/mcp-call.sh "$ACCESS"); need "$code" 200 "authorized MCP call over SVID mTLS"

# -- The four rejections (these ARE the security model) -------------------
code=$(./scripts/mcp-call-no-mtls.sh "$ACCESS");        need "$code" 000_or_4xx "no client cert -> rejected"        # TODO exact expectation
code=$(./scripts/mcp-call.sh "$(./scripts/mint-wrong-aud-token.sh)"); need "$code" 401 "wrong-audience token -> 401"
code=$(./scripts/mcp-call-with-svid-as-bearer.sh);      need "$code" 401 "JWT-SVID as bearer -> 401"
code=$(./scripts/mcp-call-unlisted-workload.sh "$ACCESS"); need "$code" 403 "unlisted SPIFFE ID -> 403"

# -- Chain of custody -----------------------------------------------------
./scripts/verify-chain.sh && say "SVID chains to EJBCA root, constraint enforced" PASS || { say "chain" FAIL; FAIL=1; }
grep -q '"act"' logs/mcp-server.log && say "act.sub logged on calls" PASS || { say "act logging" FAIL; FAIL=1; }

exit $FAIL
