#!/usr/bin/env bash
# Stage recovery (DEMO-PLAN P5).
#   --soft : restart the app layer only (mcp-server, agent-web) and re-run the
#            idempotent setup. The common stage recovery; target < 2 min.
#   --full : docker compose down + up, ALL volumes kept. Deterministic, ~3 min.
#   --cold : DESTROYS the SPIRE/EJBCA state volumes and rebuilds from nothing.
#            Asks first — this is the ask-first boundary of CLAUDE.md §7.
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:---soft}"
START=$(date +%s)

case "$MODE" in
  --cold)
    echo "COLD RESET deletes the SPIRE and EJBCA volumes (CA state, registrations)."
    read -r -p "Type 'yes' to proceed: " ok
    [ "$ok" = "yes" ] || { echo "aborted"; exit 1; }
    (cd infra && docker compose --profile demo --profile pki --profile tools down -v)
    echo "Volumes gone. Re-running full setup (EJBCA hierarchy takes a while)..."
    bash infra/pki/setup-ejbca.sh
    # M12: employee profiles + the RA credential for cert-service (this script
    # is human-gated, but --cold is itself human-run, so chaining is in-bounds)
    bash infra/pki/setup-employee-profile.sh --force
    ;;
  --full)
    (cd infra && docker compose --profile demo down) >/dev/null
    ;;
  --soft)
    (cd infra && docker compose restart mcp-server agent-web) >/dev/null 2>&1 || true
    ;;
  *)
    echo "usage: demo/reset.sh [--soft|--full|--cold]"; exit 2
    ;;
esac

bash infra/pki/issue-bundle-endpoint-cert.sh >/dev/null
(cd infra && docker compose up -d --wait spire-server spire-agent keycloak) >/dev/null
bash infra/spire/register-workloads.sh >/dev/null
bash infra/keycloak/setup-realm.sh >/dev/null
bash infra/keycloak/setup-spiffe-idp.sh >/dev/null
bash infra/keycloak/setup-demo-web.sh >/dev/null
bash infra/keycloak/setup-two-hop.sh >/dev/null
# pki profile: ejbca must run for the M12 issuance leg (no healthcheck defined,
# so --wait only sees "running"; cert-service reads its RA credential lazily).
(cd infra && docker compose --profile demo --profile pki up -d --wait --wait-timeout 300) >/dev/null
bash infra/ollama/pull-model.sh >/dev/null
echo "RESET OK ($MODE) in $(( $(date +%s) - START ))s — stack + demo + pki profiles up, model present"
