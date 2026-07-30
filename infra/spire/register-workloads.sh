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

for w in agent-client mcp-server; do
  ID="spiffe://lab.internal/${w}"
  if srv entry show -spiffeID "$ID" | grep -q "$ID"; then
    echo "entry exists: $ID"
  else
    srv entry create -parentID "$PARENT" -spiffeID "$ID" \
      -selector "docker:label:org.lab.workload:${w}"
    echo "entry created: $ID (parent $PARENT)"
  fi
done
