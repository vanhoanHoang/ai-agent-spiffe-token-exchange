#!/usr/bin/env bash
# Carry the built and pulled images to another machine on a USB stick, so the
# first launch there needs neither a 10-minute build nor the venue's wifi.
#   bash demo/export-images.sh <dir>     # writes <dir>/spiffe-mcp-lab-images.tar (+ .txt manifest)
# Ollama's image is deliberately excluded (hosted provider: it never runs; local
# provider: `docker compose pull ollama` is the cheap part, the model is not —
# that one lives in a volume and is pulled by infra/ollama/pull-model.sh).
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:?usage: demo/export-images.sh <dir>}"
mkdir -p "$OUT"

imgs=$(cd infra && docker compose --profile demo --profile pki --profile tools config --images 2>/dev/null | sort -u)
missing=0
for i in $imgs; do
  docker image inspect "$i" >/dev/null 2>&1 || { echo "MISSING: $i (build/pull first: demo/up.sh)"; missing=1; }
done
[ "$missing" -eq 0 ] || exit 1

printf '%s\n' $imgs > "$OUT/spiffe-mcp-lab-images.txt"
echo "Saving $(echo "$imgs" | wc -l | tr -d ' ') images (a few GB, minutes)..."
# shellcheck disable=SC2086
docker save -o "$OUT/spiffe-mcp-lab-images.tar" $imgs
ls -la "$OUT/spiffe-mcp-lab-images.tar"
echo "OK: on the other machine run  bash demo/import-images.sh $OUT"
