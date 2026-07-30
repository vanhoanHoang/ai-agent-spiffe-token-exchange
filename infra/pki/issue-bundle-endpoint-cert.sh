#!/usr/bin/env bash
# M6: TLS serving cert for SPIRE's federation bundle endpoint (https_web).
# Signed by the SpireIntermediate key held on disk; DNS SAN "spire-server"
# (the in-network hostname Keycloak dials). The URI name constraint on the
# intermediate does not constrain DNS names (RFC 5280 constraints are per
# name-type), and Keycloak chains leaf -> intermediate -> LabRoot via its
# truststore (--truststore-paths=ejbca-root.pem) — the lab's stand-in for
# "server certs via Web PKI" (draft §3.2 model, D-007).
# Output (gitignored): bundle-endpoint.crt.pem (leaf+intermediate), bundle-endpoint.key.pem
set -euo pipefail
cd "$(dirname "$0")"

[ -f spire-intermediate.pem ] && [ -f spire-intermediate-key.pem ] || { echo "run setup-ejbca.sh first"; exit 1; }
if [ -f bundle-endpoint.crt.pem ] && openssl x509 -in bundle-endpoint.crt.pem -noout -checkend 86400 >/dev/null 2>&1; then
  echo "bundle-endpoint cert present and valid"; exit 0
fi

openssl ecparam -name prime256v1 -genkey -noout -out bundle-endpoint.key.pem
chmod 600 bundle-endpoint.key.pem
MSYS_NO_PATHCONV=1 openssl req -new -key bundle-endpoint.key.pem -subj "/O=spiffe-mcp-lab/CN=spire-server" -out .be.csr
printf "subjectAltName=DNS:spire-server\nbasicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=serverAuth\n" > .be.ext
openssl x509 -req -in .be.csr -CA spire-intermediate.pem -CAkey spire-intermediate-key.pem \
  -CAcreateserial -out .be.leaf.pem -days 825 -extfile .be.ext
cat .be.leaf.pem spire-intermediate.pem > bundle-endpoint.crt.pem
rm -f .be.csr .be.ext .be.leaf.pem

openssl verify -CAfile ejbca-root.pem -untrusted spire-intermediate.pem bundle-endpoint.crt.pem >/dev/null \
  || { echo "FATAL: bundle-endpoint cert does not chain to EJBCA root"; exit 1; }
echo "bundle-endpoint cert issued (DNS:spire-server, chains to LabRoot)"
