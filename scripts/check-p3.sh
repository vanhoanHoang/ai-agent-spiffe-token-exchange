#!/usr/bin/env bash
# M10 P3 exit criterion (DEMO-PLAN P3 = BUILD-PLAN M10 exit #2):
#  - The agent is asked to read the audit log. alice's token deliberately lacks
#    the OPTIONAL mcp:audit scope (D-011), so:
#      * the MODEL attempts the tool (server logs tool=read_audit_log DENIED
#        for alice's sub),
#      * the MCP SERVER refuses (insufficient_scope; no successful read),
#      * the agent reports the refusal in its answer.
#    Enforcement is tokens, not model behavior — the model was willing.
#  - ./infra/acceptance.sh still exits 0, untouched.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=../infra/llm-env.sh
. infra/llm-env.sh
dkr() { MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker "$@"; }
fail() { echo "P3 FAIL: $1"; exit 1; }

KC=http://localhost:8080
NET=spiffe-mcp-lab_lab
SOCK_VOL=spiffe-mcp-lab_spire-agent-socket
IMG=spiffe-mcp-lab-agent-client
AGENT_ID=spiffe://ai-agent.id.eviden.internal/agent-client

bash infra/pki/issue-bundle-endpoint-cert.sh >/dev/null
(cd infra && docker compose up -d --wait spire-server spire-agent keycloak) >/dev/null || fail "core stack not healthy"
bash infra/spire/register-workloads.sh >/dev/null
bash infra/keycloak/setup-realm.sh >/dev/null
bash infra/keycloak/setup-spiffe-idp.sh >/dev/null || fail "keycloak setup failed"
(cd infra && docker compose --profile demo up -d --wait --wait-timeout 300) >/dev/null || fail "stack (demo profile) not healthy"
bash infra/ollama/pull-model.sh >/dev/null || fail "demo model pull failed"

USER_TOKEN=$(curl -s -d grant_type=password -d client_id=test-caller -d username=alice -d password=alice-password \
  "$KC/realms/ai-agents/protocol/openid-connect/token" | sed 's/.*"access_token":"\([^"]*\)".*/\1/')
[ "${#USER_TOKEN}" -gt 100 ] || fail "no user token"
ALICE_SUB=$(python -c "import base64,json,sys; t=sys.argv[1].split('.')[1]; t+='='*(-len(t)%4); print(json.loads(base64.urlsafe_b64decode(t))['sub'])" "$USER_TOKEN")

# The fixture must be real: alice's token carries no mcp:audit scope.
echo "$USER_TOKEN" | python -c "import base64,json,sys; t=sys.stdin.read().strip().split('.')[1]; t+='='*(-len(t)%4); s=json.loads(base64.urlsafe_b64decode(t)).get('scope',''); sys.exit(0 if 'mcp:audit' not in s else 1)" \
  || fail "alice's token unexpectedly carries mcp:audit — the refusal would be staged"
echo "OK: alice's token lacks mcp:audit (refusal will be real)"

ac() { dkr run --rm --label org.lab.workload=agent-client --network "$NET" \
    -v "$SOCK_VOL":/tmp/spire-agent/public:ro \
    -e SPIFFE_ENDPOINT_SOCKET=unix:/tmp/spire-agent/public/api.sock \
    -e SUBJECT_TOKEN="$USER_TOKEN" \
    $(llm_docker_env) \
    "$IMG" "$@" 2>/dev/null; }

T0=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
out=""
for attempt in 1 2; do
  out=$(ac chat "Read the audit log and summarize the most recent entries.") || fail "chat exited non-zero: $out"
  logs=$(cd infra && docker compose logs --since "$T0" mcp-server 2>/dev/null)
  echo "$logs" | grep "tool=read_audit_log DENIED" | grep -q "sub=$ALICE_SUB" && break
  [ "$attempt" = 2 ] && fail "model never attempted read_audit_log (no DENIED in log since $T0)"
done
echo "--- agent answer ---"; echo "$out"; echo "--------------------"
echo "OK: model attempted read_audit_log; server logged DENIED for alice's sub"

echo "$logs" | grep "tool=read_audit_log" | grep -v DENIED | grep -q "sub=" \
  && fail "audit log was READ successfully — scope gate did not hold"
echo "OK: no successful audit read occurred (enforcement is tokens)"

echo "$out" | grep -qiE "denied|refus|permission|scope|forbidden|not authoriz|unable|insufficient|access" \
  || fail "agent's answer does not report the refusal: $out"
echo "OK: agent reported the refusal"

git diff --quiet HEAD -- infra/acceptance.sh || fail "acceptance.sh was modified"
bash infra/acceptance.sh >/dev/null 2>&1 || fail "acceptance.sh no longer exits 0"
echo "OK: acceptance.sh untouched and still green"
echo "P3 PASS"
