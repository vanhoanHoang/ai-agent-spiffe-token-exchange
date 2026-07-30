#!/usr/bin/env bash
# M0 exit criterion, executable (BUILD-PLAN M0):
# DECISIONS.md D-001 must be RESOLVED from the 26.6.0 *source*, naming either
#   (a) the exact feature flag, with the compose VERIFY marker on --features gone, or
#   (b) absent -> workstream B builds the custom ClientAuthenticator SPI.
set -euo pipefail
cd "$(dirname "$0")/.."
D=docs/DECISIONS.md
fail() { echo "M0 FAIL: $1"; exit 1; }

d001=$(awk '/^## D-001/{f=1;next} /^## D-00[2-9]/{f=0} f' "$D")
[ -n "$d001" ] || fail "no D-001 entry in $D"

echo "$d001" | grep -q "RESOLVED" || fail "D-001 not RESOLVED"
echo "$d001" | grep -qi "PARTIALLY RESOLVED" && fail "D-001 still only partially resolved (release notes, not source)"
echo "$d001" | grep -q "26.6.0" || fail "D-001 does not name the Keycloak version"
echo "$d001" | grep -qiE "from (the )?source|source tree|\.java" || fail "D-001 evidence does not cite the source tree"

if echo "$d001" | grep -q "(b) absent"; then
  echo "M0 PASS: outcome (b) — custom SPI route recorded"
  exit 0
fi

# outcome (a): exact flag recorded and compose no longer carries the blanket preview VERIFY
echo "$d001" | grep -qE -- "--features=[a-z0-9:-]+" || fail "D-001 outcome (a) lacks the exact --features string"
echo "$d001" | grep -qiE "aud.*(issuer identifier|token endpoint)" || fail "D-001 does not record the aud-validation finding"
grep -q -- "--features=preview" infra/docker-compose.yml && fail "compose still uses blanket --features=preview"
echo "M0 PASS: outcome (a) — flag recorded, compose narrowed"
