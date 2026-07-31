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
# SIGPIPE-safe existence test: `K get ... | grep -q` makes grep exit on first
# match, SIGPIPEs the docker exec upstream, and under `set -o pipefail` the
# pipeline reports failure — so an existing object reads as missing and the
# script tries to re-create it. Capture first, match second.
has() { # has <pattern> <kcadm args...>
  local pattern="$1"; shift
  local out
  out=$(K "$@" 2>/dev/null) || return 1
  printf '%s' "$out" | grep -q -- "$pattern"
}

client_id() { K get clients -r lab -q clientId="$1" --fields id 2>/dev/null | tr -d ' \n' | sed 's/.*"id":"\([^"]*\)".*/\1/'; }

K config credentials --server http://localhost:8080 --realm master --user admin --password admin

if has spiffe get identity-provider/instances/spiffe -r lab --fields alias; then
  say "identity provider spiffe exists"
else
  say "creating spiffe identity provider (bundle endpoint configured out of band)"
  K create identity-provider/instances -r lab -s alias=spiffe -s providerId=spiffe -s enabled=true \
    -s 'config.trustDomain=spiffe://lab.internal' \
    -s 'config.bundleEndpoint=https://spire-server:8443'
fi

if has agent-client get clients -r lab -q clientId=agent-client --fields clientId; then
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
has federated-jwt get "clients/$CID" -r lab --fields clientAuthenticatorType \
  || { echo "FATAL: agent-client authenticator is not federated-jwt"; exit 1; }

# ---- M7: standard token exchange + act mapper ----------------------------
# Enablement attribute verified in 26.6.0 source (OIDCConfigAttributes:95).
K update "clients/$CID" -r lab -s 'attributes."standard.token.exchange.enabled"=true'
say "standard token exchange enabled on agent-client"

if has act-spiffe get "clients/$CID/protocol-mappers/models" -r lab; then
  say "act-spiffe mapper attached"
else
  say "attaching act-spiffe protocol mapper (workstream B jar)"
  K create "clients/$CID/protocol-mappers/models" -r lab \
    -s name=act-spiffe -s protocol=openid-connect -s protocolMapper=act-spiffe-mapper -s 'config={}'
fi

# Subject-token rule (StandardTokenExchangeProvider: "reject if the
# requester-client is not in the audience of the subject token"): tokens that
# alice hands to the agent must carry aud=agent-client.
AG_SCOPE_ID=$(K get client-scopes -r lab --fields id,name 2>/dev/null | tr -d ' \n' | grep -o '{"id":"[^"]*","name":"agent-audience"}' | sed 's/.*"id":"\([^"]*\)".*/\1/' || true)
if [ -z "$AG_SCOPE_ID" ]; then
  say "creating client-scope agent-audience (aud=agent-client on user tokens)"
  AG_SCOPE_ID=$(K create client-scopes -r lab -s name=agent-audience -s protocol=openid-connect -i)
  K create "client-scopes/$AG_SCOPE_ID/protocol-mappers/models" -r lab \
    -s name=agent-aud -s protocol=openid-connect -s protocolMapper=oidc-audience-mapper \
    -s 'config."included.client.audience"=agent-client' \
    -s 'config."access.token.claim"=true'
fi
TC_ID=$(client_id test-caller)
K update "clients/$TC_ID/default-client-scopes/$AG_SCOPE_ID" -r lab

# ---- M10 P1/P3: mcp:audit is an OPTIONAL scope --------------------------
# Deliberately not default: alice's demo token lacks it, so the scope-gated
# read_audit_log tool is refused (enforcement is tokens, not model behavior).
if has '"mcp:audit"' get client-scopes -r lab --fields name; then
  say "client-scope mcp:audit exists"
else
  say "creating optional client-scope mcp:audit (NOT default — P3 fixture)"
  AUD_SCOPE_ID=$(K create client-scopes -r lab -s name=mcp:audit -s protocol=openid-connect \
    -s 'attributes."include.in.token.scope"=true' -i)
  K update "clients/$CID/optional-client-scopes/$AUD_SCOPE_ID" -r lab
  K update "clients/$TC_ID/optional-client-scopes/$AUD_SCOPE_ID" -r lab
fi
say "spiffe idp + agent-client ready (federated-jwt, token exchange, act mapper)"
