#!/usr/bin/env bash
# Load the images written by demo/export-images.sh. Afterwards demo/up.sh
# reuses them (compose only builds what is missing) — no build, no registry.
#   bash demo/import-images.sh <dir>
set -euo pipefail
cd "$(dirname "$0")/.."
IN="${1:?usage: demo/import-images.sh <dir>}"
TAR="$IN/spiffe-mcp-lab-images.tar"
[ -f "$TAR" ] || { echo "not found: $TAR"; exit 1; }
docker info >/dev/null 2>&1 || { echo "start Docker Desktop first"; exit 1; }
echo "Loading $TAR (minutes)..."
docker load -i "$TAR"
echo
echo "Present now:"
while read -r i; do
  docker image inspect "$i" >/dev/null 2>&1 && echo "  OK      $i" || echo "  MISSING $i"
done < "$IN/spiffe-mcp-lab-images.txt"
echo "Next: bash demo/up.sh --check"
