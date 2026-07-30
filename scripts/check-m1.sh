#!/usr/bin/env bash
# M1 exit criterion (BUILD-PLAN M1): docker compose up -d && every default-profile
# service reaches healthy. Fails if any service is missing, unhealthy, or has no healthcheck.
set -euo pipefail
cd "$(dirname "$0")/../infra"

docker compose up -d --wait --wait-timeout 180 || true

fail=0
services=$(docker compose config --services)
[ -n "$services" ] || { echo "M1 FAIL: no services in default profile"; exit 1; }

for s in $services; do
  status=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' \
    "$(docker compose ps -q "$s" 2>/dev/null)" 2>/dev/null || echo missing)
  printf '%-14s %s\n' "$s" "$status"
  [ "$status" = "healthy" ] || fail=1
done

[ $fail -eq 0 ] && echo "M1 PASS: all default-profile services healthy" || { echo "M1 FAIL"; exit 1; }
