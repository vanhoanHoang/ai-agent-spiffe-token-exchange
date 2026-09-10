#!/usr/bin/env bash
# M10 P2 exit criterion (DEMO-PLAN P2 = BUILD-PLAN M10 exits #1 and #3):
#  - A natural-language request to the agent produces an MCP call whose
#    mcp-server log shows sub=alice AND act={sub=<agent SPIFFE ID>} — the
#    model chose WHAT to call; SVID -> exchange -> mTLS decided AS WHOM.
#  - Zero LLM credentials exist anywhere in the DEFAULT configuration (local
#    Ollama, compose profile "llm-local") — asserted by grep, not by promise.
#    D-039 amended the grep from words ("openai", "api-key") to VALUES: the
#    hosted path binds a key from the environment with an empty default, so a
#    key-shaped literal is the thing that must never exist in the repo.
#  - Containment (M10 isolation rule, executable): no provider-specific
#    org.springframework.ai.<provider> type outside the one config class.
#  - ./infra/acceptance.sh still exits 0, byte-identical to HEAD.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=../infra/llm-env.sh
. infra/llm-env.sh
dkr() { MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker "$@"; }
fail() { echo "P2 FAIL: $1"; exit 1; }

KC=http://localhost:8080
NET=spiffe-mcp-lab_lab
SOCK_VOL=spiffe-mcp-lab_spire-agent-socket
IMG=spiffe-mcp-lab-agent-client
TOKEN_EP=http://keycloak:8080/realms/ai-agents/protocol/openid-connect/token
MCP_EP=https://mcp.ai-agent.id.eviden.internal:8443/mcp
AGENT_ID=spiffe://ai-agent.id.eviden.internal/agent-client

# ---- 1. Containment grep (static; runs before anything needs docker) --------
# Provider-neutral spring-ai packages are allowed everywhere; anything else
# under org.springframework.ai.* is a provider package and may appear in at
# most ONE config class. Allowlist (not a provider denylist) so an unknown
# provider fails closed.
NEUTRAL='chat|mcp|model|tool|tokenizer|converter|content|template|retry|util|support|observation|aot|embedding|document|prompt'
ALLOWED_FILE='agent-client/src/main/java/internal/lab/agent/LlmProviderConfig.java'
offenders=$(grep -rloP "org\.springframework\.ai\.(?!(${NEUTRAL})\b)[a-z0-9]+" agent-client/src --include='*.java' 2>/dev/null \
  | grep -v -F "$ALLOWED_FILE" || true)
[ -z "$offenders" ] || fail "provider type outside the one config class: $offenders"
echo "OK: containment — no org.springframework.ai.<provider> type outside ${ALLOWED_FILE##*/}"

# ---- 2. Zero LLM credentials ------------------------------------------------
# No credential VALUE anywhere in agent-client source/config or compose: a
# key-shaped literal, or a key assignment whose value is not an env placeholder
# (D-039). The default provider must remain the credential-free local one.
keys=$(grep -rniE '(gsk_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9_-]{20,}|(api[_-]?key|LLM_API_KEY)[[:space:]]*[:=][[:space:]]*["'"'"']?[A-Za-z0-9_-]{16,})' \
  agent-client/src agent-client/pom.xml infra/docker-compose.yml 2>/dev/null || true)
[ -z "$keys" ] || fail "LLM-credential value found: $keys"
grep -q '^spring\.ai\.model\.chat=\${LLM_PROVIDER:ollama}$' agent-client/src/main/resources/application.properties \
  || fail "default LLM provider is not the credential-free local one"
grep -q '^spring\.ai\.openai\.api-key=\${LLM_API_KEY:}$' agent-client/src/main/resources/application.properties \
  || fail "hosted key must bind to the environment with an EMPTY default"
echo "OK: zero LLM credential values in source, config, and compose; default provider = ollama (this run: $LLM_PROVIDER)"

# ---- 3. Stack up, demo profile included ------------------------------------
bash infra/pki/issue-bundle-endpoint-cert.sh >/dev/null
(cd infra && docker compose up -d --wait spire-server spire-agent keycloak) >/dev/null || fail "core stack not healthy"
bash infra/spire/register-workloads.sh >/dev/null
bash infra/keycloak/setup-realm.sh >/dev/null
bash infra/keycloak/setup-spiffe-idp.sh >/dev/null || fail "keycloak setup failed"
(cd infra && docker compose --profile demo up -d --wait --wait-timeout 300) >/dev/null || fail "stack (demo profile) not healthy"
bash infra/ollama/pull-model.sh >/dev/null || fail "demo model pull failed"   # starts ollama only when it is the provider

USER_TOKEN=$(curl -s -d grant_type=password -d client_id=test-caller -d username=alice -d password=alice-password \
  "$KC/realms/ai-agents/protocol/openid-connect/token" | sed 's/.*"access_token":"\([^"]*\)".*/\1/')
[ "${#USER_TOKEN}" -gt 100 ] || fail "no user token"

# "sub = alice" in the log means: the exchanged token's sub equals the sub of
# alice's OWN subject token (Keycloak subs are UUIDs, not usernames) — the
# human survived the exchange, not merely someone.
ALICE_SUB=$(python -c "import base64,json,sys; t=sys.argv[1].split('.')[1]; t+='='*(-len(t)%4); print(json.loads(base64.urlsafe_b64decode(t))['sub'])" "$USER_TOKEN")
[ -n "$ALICE_SUB" ] || fail "could not decode alice's sub"

ac() { dkr run --rm --label org.lab.workload=agent-client --network "$NET" \
    -v "$SOCK_VOL":/tmp/spire-agent/public:ro \
    -e SPIFFE_ENDPOINT_SOCKET=unix:/tmp/spire-agent/public/api.sock \
    -e SUBJECT_TOKEN="$USER_TOKEN" \
    $(llm_docker_env) \
    "$IMG" "$@" 2>/dev/null; }

# ---- 4. The natural-language request (M10 exit #1) --------------------------
# Marker so the log assertion only accepts calls made by THIS chat run.
T0=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
out=$(ac chat "Use the whoami tool, then state which workload and which human you are acting for." ) \
  || fail "chat mode exited non-zero: $out"
[ -n "$out" ] || fail "chat mode produced no output"
echo "--- agent answer ---"; echo "$out"; echo "--------------------"

logs=$(cd infra && docker compose logs --since "$T0" mcp-server 2>/dev/null)
echo "$logs" | grep "tool=whoami" | grep "sub=$ALICE_SUB" | grep -q "act={sub=$AGENT_ID}" \
  || fail "server log since $T0 lacks tool=whoami with sub=$ALICE_SUB (alice) and act.sub=$AGENT_ID"
echo "OK: natural language -> MCP call; server logged sub=$ALICE_SUB (alice) act.sub=$AGENT_ID"

# ---- 5. acceptance.sh untouched and still green (M10 exit #3) ---------------
git diff --quiet HEAD -- infra/acceptance.sh || fail "acceptance.sh was modified"
bash infra/acceptance.sh >/dev/null 2>&1 || fail "acceptance.sh no longer exits 0"
echo "OK: acceptance.sh untouched and still green"
echo "P2 PASS"
