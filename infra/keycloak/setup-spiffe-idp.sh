#!/usr/bin/env bash
# M6: SPIFFE trust relationship + federated client in the lab realm.
# Config surface verified from the 26.6.0 source tree (D-001):
#   identity provider providerId=spiffe, config {trustDomain, bundleEndpoint}
#   client agent-client: clientAuthenticatorType=federated-jwt,
#     attributes jwt.credential.issuer=<idp alias>, jwt.credential.sub=<SPIFFE ID>
# NO client secret exists for agent-client — that absence IS the milestone.
set -euo pipefail
cd "$(dirname "$0")/.."

K() { MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh "$@"; }
say() { echo "== $*"; }

K config credentials --server http://localhost:8080 --realm master --user admin --password admin

if K get identity-provider/instances/spiffe -r lab --fields alias 2>/dev/null | grep -q spiffe; then
  say "identity provider spiffe exists"
else
  say "creating spiffe identity provider (bundle endpoint configured out of band)"
  K create identity-provider/instances -r lab -s alias=spiffe -s providerId=spiffe -s enabled=true \
    -s 'config.trustDomain=spiffe://lab.internal' \
    -s 'config.bundleEndpoint=https://spire-server:8443'
fi

if K get clients -r lab -q clientId=agent-client --fields clientId 2>/dev/null | grep -q agent-client; then
  say "client agent-client exists"
else
  say "creating federated client agent-client (jwt-spiffe, no secret)"
  K create clients -r lab -s clientId=agent-client -s enabled=true -s publicClient=false \
    -s serviceAccountsEnabled=true -s standardFlowEnabled=false \
    -s clientAuthenticatorType=federated-jwt \
    -s 'attributes."jwt.credential.issuer"=spiffe' \
    -s 'attributes."jwt.credential.sub"=spiffe://lab.internal/agent-client'
fi

CID=$(K get clients -r lab -q clientId=agent-client --fields id 2>/dev/null | tr -d ' \n' | sed 's/.*"id":"\([^"]*\)".*/\1/')
SCOPE_ID=$(K get client-scopes -r lab --fields id,name 2>/dev/null | tr -d ' \n' | grep -o '{"id":"[^"]*","name":"mcp-audience"}' | sed 's/.*"id":"\([^"]*\)".*/\1/')
[ -n "$SCOPE_ID" ] && K update "clients/$CID/default-client-scopes/$SCOPE_ID" -r lab && say "mcp-audience scope attached"

# Keycloak auto-generates a secret ROW for every confidential client; with
# clientAuthenticatorType=federated-jwt it is not an accepted credential.
# check-m6.sh proves that empirically (auth with the generated value must fail).
K get "clients/$CID" -r lab --fields clientAuthenticatorType 2>/dev/null | grep -q "federated-jwt" \
  || { echo "FATAL: agent-client authenticator is not federated-jwt"; exit 1; }
say "spiffe idp + agent-client ready (authenticator=federated-jwt)"
