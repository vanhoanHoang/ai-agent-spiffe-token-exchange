#!/usr/bin/env bash
# One-command launch: preflight -> reset --full -> checklist --full.
# Same command on a fresh machine, after a reboot, or after a `down`.
#   --check : preflight only, touch nothing.
#
# The preflight encodes the launch failures actually seen in the field:
#   - a foreign stack holding one of our host ports ("port is already allocated"
#     halfway through compose up, stack left partially created);
#   - the one-time gitignored artifacts missing on a fresh machine (obscure
#     SPIRE/Keycloak/EJBCA errors much later);
#   - bare `docker compose up` after a `down` (volume-less Keycloak realm gone,
#     agent-web crashloops with "Realm does not exist") — avoided here by always
#     going through reset.sh, which re-runs the idempotent realm setup.
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0
say() { printf '%-60s %s\n' "$1" "$2"; }
ok()  { say "$1" "OK"; }
bad() { say "$1" "FAIL — $2"; fail=1; }

# 1. Docker daemon.
if docker info >/dev/null 2>&1; then ok "docker daemon answering"
else say "docker daemon" "FAIL — start Docker Desktop first"; echo; exit 1; fi

# 2. Host ports this stack binds: 8080 keycloak, 8083+8444 ejbca, 8090
#    agent-web, 8443 mcp-server. Our own containers are fine (reset.sh cycles
#    them); anything else must be stopped first.
for p in 8080 8083 8090 8443 8444; do
  holder=$(docker ps --format '{{.Names}} {{.Ports}}' \
           | awk -v pat=":${p}->" 'index($0, pat) {print $1; exit}')
  if [ -n "$holder" ]; then
    case "$holder" in
      spiffe-mcp-lab-*) ok "port $p (our own $holder)" ;;
      *) bad "port $p" "held by '$holder' — docker stop $holder" ;;
    esac
  elif netstat -an 2>/dev/null | grep -Eq "[:.]${p}[[:space:]].*(LISTEN|LISTENING)"; then
    bad "port $p" "a non-docker process is listening (Windows: netstat -ano | findstr :$p)"
  else
    ok "port $p free"
  fi
done

# 3. One-time gitignored artifacts (machine-local by design, README "fresh
#    machine" step 3). These scripts are human-run — this launcher points at
#    them, it does not run them.
if [ -f infra/spire/bootstrap/agent-cacert.pem ]; then ok "SPIRE bootstrap CA"
else bad "SPIRE bootstrap CA" "run: bash infra/spire/gen-bootstrap.sh"; fi
if [ -f infra/pki/spire-intermediate.pem ] && [ -f infra/pki/ejbca-root.pem ]; then ok "EJBCA hierarchy"
else bad "EJBCA hierarchy" "run: bash infra/pki/setup-ejbca.sh"; fi
if [ -f infra/pki/ra/ra-cert-service.p12 ] && [ -f infra/pki/ra/ejbca-tls-ca.pem ]; then ok "RA credential (M12)"
else bad "RA credential (M12)" "run: bash infra/pki/setup-employee-profile.sh"; fi

echo
if [ "$fail" -ne 0 ]; then
  echo "PREFLIGHT FAIL — fix the lines above, then re-run demo/up.sh"
  exit 1
fi
echo "PREFLIGHT PASS"
[ "${1:-}" = "--check" ] && exit 0
echo

# 4. The launch itself. Deterministic; recreates the volume-less Keycloak realm.
bash demo/reset.sh --full

# 5. Trust nothing unverified.
bash demo/checklist.sh --full

echo
echo "Console: http://localhost:8090  (alice / alice-password)"
