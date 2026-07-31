#!/usr/bin/env bash
# Pre-pull the demo model into the ollama volume (idempotent). The model tag is
# pinned in docs/VERSIONS.md (D-010); the runtime never pulls
# (spring.ai.ollama.init.pull-model-strategy=never).
set -euo pipefail
cd "$(dirname "$0")/.."

MODEL=qwen3.5:4b

docker compose --profile demo up -d --wait ollama >/dev/null

if docker compose --profile demo exec -T ollama ollama list 2>/dev/null | grep -q "$MODEL"; then
  echo "OK: $MODEL already present"
  exit 0
fi

echo "Pulling $MODEL (one-time, a few GB)..."
docker compose --profile demo exec -T ollama ollama pull "$MODEL"
echo "OK: $MODEL pulled"
