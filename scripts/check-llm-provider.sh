#!/usr/bin/env bash
# LLM provider switch (D-039): the model is a deployment detail selected by
# environment, never by code. Exit criterion:
#  1. Default configuration (no LLM_* env) is local Ollama and holds ZERO
#     credentials — the P2 claim survives, now asserted on credential VALUES
#     (a key-shaped literal) rather than on the words "openai"/"api-key".
#  2. Ollama is no longer part of the `demo` profile: with LLM_PROVIDER=openai
#     the stack starts without the container and without the 2-3 GB pull.
#  3. Selection is Spring AI's own switch (`spring.ai.model.chat`, verified
#     from the autoconfigure jars) bound to LLM_PROVIDER; both wire starters
#     are in the build; still no provider type in Java (check-p2.sh §3).
#  4. When LLM_PROVIDER=openai: a key is present, the endpoint answers with
#     that key, and the pinned model is in its catalog.
# The runtime gate for the hosted path is `LLM_PROVIDER=openai scripts/check-p2.sh`
# (same chat, same sub=alice/act=agent assertion) — this script is the static half.
set -euo pipefail
cd "$(dirname "$0")/.."
fail() { echo "LLM-PROVIDER FAIL: $1"; exit 1; }

[ -f infra/llm-env.sh ] || fail "infra/llm-env.sh missing (single source of LLM_* defaults)"
# shellcheck source=../infra/llm-env.sh
. infra/llm-env.sh

# One service's block of the rendered compose config (the range end excludes
# the start line, so the block is the whole service, not just its header).
svc_block() { awk -v s="  $1:" '$0==s{f=1;print;next} f&&/^  [a-z-]+:$/{f=0} f'; }
demo_cfg() { (cd infra && docker compose --profile demo config 2>/dev/null); }

# ---- 1. Zero credential VALUES anywhere in the repo --------------------------
# A key-shaped literal (Groq gsk_…, OpenAI sk-…, or any key assignment whose
# value is not an env placeholder). Env placeholders `${LLM_API_KEY:…}` are the
# point: the value lives outside the repo or nowhere.
# "In the repo" = tracked or stageable files; the gitignored infra/.env is
# the sanctioned home of a key and must never be grepped (or echoed) here.
git check-ignore -q infra/.env || fail "infra/.env is not gitignored — a key placed there would be committed"
lit=$(git ls-files --cached --others --exclude-standard -z \
  | xargs -0 grep -nIE '(gsk_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9_-]{20,}|(api[_-]?key|LLM_API_KEY)[[:space:]]*[:=][[:space:]]*["'"'"']?[A-Za-z0-9_-]{16,})' 2>/dev/null \
  | grep -vE '^(scripts/check-llm-provider\.sh|scripts/check-p2\.sh):' | cut -d: -f1,2 || true)
[ -z "$lit" ] || fail "credential-shaped literal in a repo file (value not shown): $lit"
grep -q '^spring\.ai\.model\.chat=\${LLM_PROVIDER:ollama}$' agent-client/src/main/resources/application.properties \
  || fail "default provider is not ollama (spring.ai.model.chat=\${LLM_PROVIDER:ollama} expected)"
grep -q '^spring\.ai\.openai\.api-key=\${LLM_API_KEY:}$' agent-client/src/main/resources/application.properties \
  || fail "openai api-key must bind to LLM_API_KEY with an EMPTY default"
echo "OK: zero credential values; default provider = ollama"

# ---- 2. Ollama out of the demo profile --------------------------------------
svcs=$(cd infra && docker compose --profile demo --profile pki config --services 2>/dev/null)
echo "$svcs" | grep -qx ollama && fail "ollama still starts with --profile demo"
svcs=$(cd infra && docker compose --profile llm-local config --services 2>/dev/null)
echo "$svcs" | grep -qx ollama || fail "ollama not reachable via --profile llm-local"
demo_cfg | svc_block agent-web | grep -qE '^[[:space:]]+ollama:' \
  && fail "agent-web still depends_on ollama (startup never contacts the model; pull strategy is never)"
echo "OK: ollama is opt-in (profile llm-local), agent-web starts without it"

# ---- 3. The switch is env-bound and both wires are in the build --------------
grep -q '<artifactId>spring-ai-starter-model-ollama</artifactId>' agent-client/pom.xml || fail "ollama starter missing"
grep -q '<artifactId>spring-ai-starter-model-openai</artifactId>' agent-client/pom.xml || fail "openai starter missing"
cfg=$(demo_cfg | svc_block agent-web)
for v in LLM_PROVIDER LLM_BASE_URL LLM_MODEL LLM_API_KEY; do
  echo "$cfg" | grep -qE "^[[:space:]]+$v:" || fail "agent-web does not pass $v through"
done
grep -q 'llm_docker_env' scripts/check-p2.sh || fail "check-p2.sh ad-hoc chat container does not receive LLM_* env"
echo "OK: spring.ai.model.chat <- LLM_PROVIDER; both starters present; env plumbed to agent-web and ad-hoc runs"

# ---- 4. Hosted path, only when selected --------------------------------------
if [ "$LLM_PROVIDER" = openai ]; then
  [ -n "$LLM_API_KEY" ] || fail "LLM_PROVIDER=openai but LLM_API_KEY is empty (infra/.env or the environment)"
  body=$(curl -s --max-time 15 -H "Authorization: Bearer $LLM_API_KEY" "$LLM_BASE_URL/models") \
    || fail "$LLM_BASE_URL/models unreachable"
  echo "$body" | grep -q '"data"' || fail "endpoint refused the key: $(echo "$body" | head -c 200)"
  echo "$body" | grep -q "\"id\": *\"$LLM_MODEL\"" || fail "model '$LLM_MODEL' not in the catalog at $LLM_BASE_URL/models"
  echo "OK: $LLM_BASE_URL answers with the key; model $LLM_MODEL is in its catalog"
else
  echo "OK: LLM_PROVIDER=$LLM_PROVIDER — hosted checks skipped (set LLM_PROVIDER=openai to run them)"
fi
echo "LLM-PROVIDER PASS"
