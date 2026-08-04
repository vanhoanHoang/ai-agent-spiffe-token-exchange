#!/usr/bin/env bash
# M11 exit criterion (BUILD-PLAN M11 / DEMO-PLAN P4):
#   the console renders a complete demo run OFFLINE from captured JSON; it
#   holds no secrets, validates nothing, and killing it changes nothing.
# Executable form:
#   1. lint      — the CONVENTIONS-ANGULAR rules are wired into eslint and BLOCK
#   2. tests     — every panel renders from the checked-in capture fixture,
#                  including the negative fixtures (FAILED-TO-DENY, malformed
#                  capture -> error state, never a half-rendered lie)
#   3. build     — production bundle
#   4. offline   — the bundle references no external origin (no CDN fonts,
#                  scripts, or styles) and ships demo-run.json + local fonts
#   5. hygiene   — nothing JWT-shaped in the shipped capture
set -euo pipefail
cd "$(dirname "$0")/.."
fail() { echo "CONSOLE FAIL: $1"; exit 1; }

cd console
[ -f package-lock.json ] || fail "no lockfile"
npm ci >/dev/null 2>&1 || fail "npm ci"
rm -rf .angular   # the build cache does not survive a fresh node_modules
npm run -s lint || fail "lint (CONVENTIONS-ANGULAR rules are binding)"
echo "OK: lint"
npm test -s -- --watch=false || fail "tests"
echo "OK: tests (panels render from the capture fixture)"
npm run -s build >/dev/null || fail "build"
echo "OK: production build"

DIST=dist/console/browser
[ -f "$DIST/index.html" ] || fail "no index.html in $DIST"
[ -f "$DIST/demo-run.json" ] || fail "demo-run.json not shipped with the bundle"
if grep -RhoE '(src|href)="https?://[^"]*"' "$DIST"/*.html >/dev/null 2>&1; then
  fail "index references an external origin — offline rule broken"
fi
if grep -lE 'https?://[a-z0-9.-]*(googleapis|gstatic|cdn|unpkg|jsdelivr)' "$DIST"/*.css "$DIST"/*.js >/dev/null 2>&1; then
  fail "bundle pulls from a CDN — offline rule broken"
fi
ls "$DIST"/media/*.woff2 >/dev/null 2>&1 || ls "$DIST"/*.woff2 >/dev/null 2>&1 \
  || fail "fonts not bundled locally"
echo "OK: offline — no external origin, capture + fonts shipped"

grep -qE '[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}' "$DIST/demo-run.json" \
  && fail "shipped capture contains a JWT-shaped string" || true
echo "OK: shipped capture holds no token"

# 6. two-hop (M12/D-032) — the console must be able to TELL THE SECOND HOP.
#    A single-hop console rendering a two-hop run is a lie by omission: it
#    would show alice delegating to the assistant and stop there, silently
#    dropping the agent that actually issued the certificate. These greps are
#    coarse on purpose — they only prove the second hop reached the bundle;
#    the hop ATTRIBUTION itself is asserted in the unit tests above.
for name in agent-pki cert-service; do
  grep -q "$name" "$DIST"/*.js \
    || fail "the console cannot name $name — the second hop is invisible in the bundle"
done
echo "OK: the second hop's workloads reach the bundle"

# The refusal is load-bearing: agent-client -> cert-service must be DRAWN,
# not merely absent. An edge nobody can see proves nothing to an audience.
grep -q 'forbidden' "$DIST"/*.js \
  || fail "the refused agent-client -> cert-service path is not drawn"
echo "OK: the refused path is drawn, not just absent"
echo "CONSOLE PASS"
