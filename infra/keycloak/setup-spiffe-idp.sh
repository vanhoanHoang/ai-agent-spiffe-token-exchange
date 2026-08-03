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

client_id() { K get clients -r ai-agents -q clientId="$1" --fields id 2>/dev/null | tr -d ' \n' | sed 's/.*"id":"\([^"]*\)".*/\1/'; }

K config credentials --server http://localhost:8080 --realm master --user admin --password admin

if has spiffe get identity-provider/instances/spiffe -r ai-agents --fields alias; then
  say "identity provider spiffe exists"
else
  say "creating spiffe identity provider (bundle endpoint configured out of band)"
  K create identity-provider/instances -r ai-agents -s alias=spiffe -s providerId=spiffe -s enabled=true \
    -s 'config.trustDomain=spiffe://ai-agent.id.eviden.internal' \
    -s 'config.bundleEndpoint=https://spire-server:8443'
fi

if has agent-client get clients -r ai-agents -q clientId=agent-client --fields clientId; then
  say "client agent-client exists"
else
  say "creating federated client agent-client (jwt-spiffe, no secret)"
  K create clients -r ai-agents -s clientId=agent-client -s enabled=true -s publicClient=false \
    -s serviceAccountsEnabled=true -s standardFlowEnabled=false \
    -s clientAuthenticatorType=federated-jwt \
    -s 'attributes."jwt.credential.issuer"=spiffe' \
    -s 'attributes."jwt.credential.sub"=spiffe://ai-agent.id.eviden.internal/agent-client'
fi

CID=$(K get clients -r ai-agents -q clientId=agent-client --fields id 2>/dev/null | tr -d ' \n' | sed 's/.*"id":"\([^"]*\)".*/\1/')
SCOPE_ID=$(K get client-scopes -r ai-agents --fields id,name 2>/dev/null | tr -d ' \n' | grep -o '{"id":"[^"]*","name":"mcp-audience"}' | sed 's/.*"id":"\([^"]*\)".*/\1/')
[ -n "$SCOPE_ID" ] && K update "clients/$CID/default-client-scopes/$SCOPE_ID" -r ai-agents && say "mcp-audience scope attached"

# Keycloak auto-generates a secret ROW for every confidential client; with
# clientAuthenticatorType=federated-jwt it is not an accepted credential.
# check-m6.sh proves that empirically (auth with the generated value must fail).
has federated-jwt get "clients/$CID" -r ai-agents --fields clientAuthenticatorType \
  || { echo "FATAL: agent-client authenticator is not federated-jwt"; exit 1; }

# ---- M7: standard token exchange + act mapper ----------------------------
# Enablement attribute verified in 26.6.0 source (OIDCConfigAttributes:95).
K update "clients/$CID" -r ai-agents -s 'attributes."standard.token.exchange.enabled"=true'
say "standard token exchange enabled on agent-client"

if has act-spiffe get "clients/$CID/protocol-mappers/models" -r ai-agents; then
  say "act-spiffe mapper attached"
else
  say "attaching act-spiffe protocol mapper (workstream B jar)"
  K create "clients/$CID/protocol-mappers/models" -r ai-agents \
    -s name=act-spiffe -s protocol=openid-connect -s protocolMapper=act-spiffe-mapper -s 'config={}'
fi

# Subject-token rule (StandardTokenExchangeProvider: "reject if the
# requester-client is not in the audience of the subject token"): tokens that
# alice hands to the agent must carry aud=agent-client.
AG_SCOPE_ID=$(K get client-scopes -r ai-agents --fields id,name 2>/dev/null | tr -d ' \n' | grep -o '{"id":"[^"]*","name":"agent-audience"}' | sed 's/.*"id":"\([^"]*\)".*/\1/' || true)
if [ -z "$AG_SCOPE_ID" ]; then
  say "creating client-scope agent-audience (aud=agent-client on user tokens)"
  AG_SCOPE_ID=$(K create client-scopes -r ai-agents -s name=agent-audience -s protocol=openid-connect -i)
  K create "client-scopes/$AG_SCOPE_ID/protocol-mappers/models" -r ai-agents \
    -s name=agent-aud -s protocol=openid-connect -s protocolMapper=oidc-audience-mapper \
    -s 'config."included.client.audience"=agent-client' \
    -s 'config."access.token.claim"=true'
fi
TC_ID=$(client_id test-caller)
K update "clients/$TC_ID/default-client-scopes/$AG_SCOPE_ID" -r ai-agents

# ---- M10 P1/P3: mcp:audit is an OPTIONAL scope --------------------------
# Deliberately not default: alice's demo token lacks it, so the scope-gated
# read_audit_log tool is refused (enforcement is tokens, not model behavior).
if has '"mcp:audit"' get client-scopes -r ai-agents --fields name; then
  say "client-scope mcp:audit exists"
else
  say "creating optional client-scope mcp:audit (NOT default — P3 fixture)"
  AUD_SCOPE_ID=$(K create client-scopes -r ai-agents -s name=mcp:audit -s protocol=openid-connect \
    -s 'attributes."include.in.token.scope"=true' -i)
  K update "clients/$CID/optional-client-scopes/$AUD_SCOPE_ID" -r ai-agents
  K update "clients/$TC_ID/optional-client-scopes/$AUD_SCOPE_ID" -r ai-agents
fi
# ---- scope intersection at the exchange (workstream B executor) ----------
# CLAUDE.md §2: effective permissions = user scopes ∩ agent allowed scopes.
# Keycloak validates a requested scope against the REQUESTER's assigned scopes
# only — the subject token's scopes are never consulted — so without this
# policy an agent can request a scope the human never granted (proven live:
# a scope-gated tool returned 200 for an unconsented user). The executor
# refuses any exchange asking for more than the subject token carries.
#
# Client policies/profiles are realm-level JSON documents, not CRUD objects:
# kcadm update realms/<realm>/client-policies/{profiles,policies} replaces the
# whole document. That makes the content SINGLE-OWNER by necessity: this script
# and setup-two-hop.sh both apply it, so the JSON lives in shared files
# (delegation-{profiles,policies}.json). Two scripts carrying their own variants
# meant whichever ran last silently deleted the other's executor — observed
# live: a reset without setup-two-hop dropped the delegation table.
#
# The any-client condition in the policies file is REQUIRED, not decoration: a
# policy whose conditions list is empty matches NOTHING and is silently never
# applied (DefaultClientPolicyManager.isSatisfied: "if conditions.isEmpty()
# return false"). It looked correct in the admin API and enforced nothing —
# which is exactly how this was first written.
K update realms/ai-agents/client-policies/profiles -r ai-agents -f - < keycloak/delegation-profiles.json >/dev/null
say "client profile spiffe-delegation registered (intersection + delegation-table executors)"
K update realms/ai-agents/client-policies/policies -r ai-agents -f - < keycloak/delegation-policies.json >/dev/null
say "client policy spiffe-delegation-policy enabled (applies to all clients)"

has exchange-scope-intersection get realms/ai-agents/client-policies/profiles -r ai-agents \
  || { echo "FATAL: scope-intersection executor did not register — is the SPI jar in the image?"; exit 1; }

say "spiffe idp + agent-client ready (federated-jwt, token exchange, act mapper, scope intersection)"
