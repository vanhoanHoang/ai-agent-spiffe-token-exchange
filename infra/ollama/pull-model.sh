#!/usr/bin/env bash
# Pre-pull the demo model into the ollama volume (idempotent). The model tag is
# pinned in docs/VERSIONS.md (D-010); the runtime never pulls
# (spring.ai.ollama.init.pull-model-strategy=never).
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=../llm-env.sh
. ./llm-env.sh

# D-039: on a hosted provider the local model is neither pulled nor started —
# this script is the single place the llm-local profile is enabled, so every
# launcher that calls it gets the right shape for free.
if [ "$LLM_PROVIDER" != ollama ]; then
  echo "OK: LLM_PROVIDER=$LLM_PROVIDER — local model not used, ollama not started"
  exit 0
fi

MODEL=qwen3.5:4b

docker compose --profile llm-local up -d --wait ollama >/dev/null

if docker compose --profile llm-local exec -T ollama ollama list 2>/dev/null | grep -q "$MODEL"; then
  echo "OK: $MODEL already present"
  exit 0
fi

echo "Pulling $MODEL (one-time, a few GB)..."
docker compose --profile llm-local exec -T ollama ollama pull "$MODEL"
echo "OK: $MODEL pulled"
