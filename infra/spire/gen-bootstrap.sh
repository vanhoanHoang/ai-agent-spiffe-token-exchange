#!/usr/bin/env bash
# One-time bootstrap PKI for SPIRE x509pop NODE attestation (agent <-> server).
# This is deliberately NOT the EJBCA hierarchy: the infra/pki contract (M3) covers
# workload SVID chain-of-custody; this covers only "which node is the agent".
# Output: infra/spire/bootstrap/ (gitignored — contains private keys).
set -euo pipefail
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'   # Git Bash on Windows: don't mangle -subj into paths
cd "$(dirname "$0")"
mkdir -p bootstrap
cd bootstrap

[ -f agent-cacert.pem ] && [ -f agent.crt.pem ] && [ -f agent.key.pem ] && { echo "bootstrap PKI already present — not regenerating"; exit 0; }

# Bootstrap CA (10y)
openssl ecparam -name prime256v1 -genkey -noout -out agent-ca.key.pem
# No -addext here: `req -x509` already applies the default config's v3_ca
# (basicConstraints CA:TRUE); adding it again produces a duplicate-extension
# cert that SPIRE's x509pop loader rejects.
openssl req -new -x509 -key agent-ca.key.pem -out agent-cacert.pem -days 3650 \
  -subj "/O=spiffe-mcp-lab/CN=spire-agent-bootstrap-ca"

# Agent identity cert (1y; x509pop requires digitalSignature keyUsage)
openssl ecparam -name prime256v1 -genkey -noout -out agent.key.pem
openssl req -new -key agent.key.pem -subj "/O=spiffe-mcp-lab/CN=spire-agent" -out agent.csr.pem
printf "keyUsage=critical,digitalSignature\nbasicConstraints=critical,CA:FALSE\n" > agent.ext
openssl x509 -req -in agent.csr.pem -CA agent-cacert.pem -CAkey agent-ca.key.pem \
  -CAcreateserial -out agent.crt.pem -days 365 -extfile agent.ext
rm agent.csr.pem agent.ext

chmod 600 agent.key.pem agent-ca.key.pem
echo "bootstrap PKI written to $(pwd)"
