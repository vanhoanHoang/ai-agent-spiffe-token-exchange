#!/usr/bin/env bash
# Idempotent SPIRE registration entries for the two lab workloads (M2).
# Parent = the agent's x509pop SPIFFE ID: spiffe://lab.internal/spire/agent/x509pop/<fp>
# where <fp> is the SHA1 of the DER of the agent's bootstrap identity cert
# (specs/spire/plugin_server_nodeattestor_x509pop.md). Derived, never hardcoded —
# regenerating the bootstrap PKI changes it.
set -euo pipefail
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'
cd "$(dirname "$0")"

[ -f bootstrap/agent.crt.pem ] || { echo "missing bootstrap PKI — run gen-bootstrap.sh"; exit 1; }
FP=$(openssl x509 -in bootstrap/agent.crt.pem -outform DER | sha1sum | cut -d' ' -f1)
PARENT="spiffe://lab.internal/spire/agent/x509pop/${FP}"

srv() { (cd .. && docker compose exec -T spire-server /opt/spire/bin/spire-server "$@"); }

# SIGPIPE-safe existence test (D-011 house pattern): `... | grep -q` under
# pipefail SIGPIPEs the docker exec on first match, an existing entry reads as
# missing, and the re-create dies. Capture first, match second.
has_entry() {
  local out
  out=$(srv entry show -spiffeID "$1" 2>/dev/null) || return 1
  printf '%s' "$out" | grep -q -- "$1"
}

# test-agent: permanent fixture for the D-009 act↔peer binding rejection (M9)
for w in agent-client mcp-server test-agent; do
  ID="spiffe://lab.internal/${w}"
  if has_entry "$ID"; then
    echo "entry exists: $ID"
  else
    srv entry create -parentID "$PARENT" -spiffeID "$ID" \
      -selector "docker:label:org.lab.workload:${w}"
    echo "entry created: $ID (parent $PARENT)"
  fi
done
