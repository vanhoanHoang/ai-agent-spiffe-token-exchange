#!/usr/bin/env bash
# Run on YOUR machine (Claude Code's sandbox may not reach these hosts).
# Populates specs/ per docs/SPEC-REGISTRY.md. Idempotent.
set -euo pipefail
cd "$(dirname "$0")"

get() { [ -f "$2" ] && echo "have $2" || { echo "fetch $2"; curl -fsSL "$1" -o "$2"; }; }

get https://www.ietf.org/archive/id/draft-ietf-oauth-spiffe-client-auth-02.txt draft-ietf-oauth-spiffe-client-auth-02.txt
for n in 7521 7523 8414 8693 8705 8707 8725 9728; do
  get "https://www.rfc-editor.org/rfc/rfc${n}.txt" "rfc${n}.txt"
done

mkdir -p spiffe spire
SPIRE_TAG=v1.15.2   # keep aligned with docs/VERSIONS.md
for d in plugin_server_upstreamauthority_disk.md plugin_server_nodeattestor_x509pop.md spire_server.md spire_agent.md \
         plugin_agent_nodeattestor_x509pop.md plugin_server_datastore_sql.md plugin_server_keymanager_disk.md \
         plugin_agent_keymanager_disk.md plugin_agent_workloadattestor_docker.md; do
  get "https://raw.githubusercontent.com/spiffe/spire/${SPIRE_TAG}/doc/${d}" "spire/${d}"
done
for s in SPIFFE-ID X509-SVID JWT-SVID SPIFFE_Trust_Domain_and_Bundle SPIFFE_Federation; do
  get "https://raw.githubusercontent.com/spiffe/spiffe/main/standards/${s}.md" "spiffe/${s}.md"
done

mkdir -p keycloak
KC_TAG=26.6.0   # keep aligned with docs/VERSIONS.md
for f in services/src/main/java/org/keycloak/protocol/oidc/tokenexchange/StandardTokenExchangeProvider.java \
         services/src/main/java/org/keycloak/protocol/oidc/tokenexchange/AbstractTokenExchangeProvider.java \
         services/src/main/java/org/keycloak/protocol/oidc/grants/TokenExchangeGrantType.java \
         services/src/main/java/org/keycloak/protocol/oidc/endpoints/TokenEndpoint.java \
         services/src/main/java/org/keycloak/protocol/oidc/TokenManager.java \
         services/src/main/java/org/keycloak/services/util/DefaultClientSessionContext.java \
         server-spi-private/src/main/java/org/keycloak/protocol/oidc/TokenExchangeContext.java; do
  get "https://raw.githubusercontent.com/keycloak/keycloak/${KC_TAG}/${f}" "keycloak/$(basename "$f")"
done

echo "---- done. Also fetch manually (auth/format varies): MCP spec revision, EJBCA docs for the pinned version."
