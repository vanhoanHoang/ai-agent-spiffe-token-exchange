#!/usr/bin/env bash
# M12: the second hop's Keycloak surface.
#
# The rule this file exists to encode: NO SINGLE AGENT CAN COMPLETE THE TASK.
#   agent-client  may hold onboard:initiate     — never issue:employee-cert
#   agent-pki     may hold issue:employee-cert  — never onboard:initiate
# Non-overlap is literal here, in client scope assignment, not a convention.
#
# Audiences come from client scopes, never from the exchange's audience
# parameter, which only filters (D-008 finding 2).
set -euo pipefail
cd "$(dirname "$0")/.."

K() { MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh "$@"; }
# Status goes to stderr, data to stdout: several helpers below return an id via
# command substitution, and a stray progress line would be captured as part of
# that id (it was, the first time this ran).
say() { echo "== $*" >&2; }
# SIGPIPE-safe existence test (D-011 house pattern).
has() {
  local pattern="$1"; shift
  local out
  out=$(K "$@" 2>/dev/null) || return 1
  printf '%s' "$out" | grep -q -- "$pattern"
}
# kcadm answers "[]" for a client that does not exist, and "[]" is not empty —
# it sails past a -n guard and lands in a URL path as a literal bracket.
client_id() {
  local out
  out=$(K get clients -r ai-agents -q clientId="$1" --fields id 2>/dev/null | tr -d ' \n')
  case "$out" in
    *'"id"'*) printf '%s' "$out" | sed 's/.*"id":"\([^"]*\)".*/\1/' ;;
    *) printf '' ;;
  esac
}
scope_id() { K get client-scopes -r ai-agents --fields id,name 2>/dev/null | tr -d ' \n' \
  | grep -o "{\"id\":\"[^\"]*\",\"name\":\"$1\"}" | sed 's/.*"id":"\([^"]*\)".*/\1/' || true; }

TRUST_DOMAIN=spiffe://ai-agent.id.eviden.internal
PKI_RESOURCE=https://pki-agent.ai-agent.id.eviden.internal:8445
CERT_RESOURCE=https://cert.ai-agent.id.eviden.internal:8444

K config credentials --server http://localhost:8080 --realm master --user admin --password admin

# ---- 1. agent-pki: a federated-jwt client, exactly like agent-client --------
if has agent-pki get clients -r ai-agents -q clientId=agent-pki --fields clientId; then
  say "client agent-pki exists"
else
  say "creating federated client agent-pki (jwt-spiffe, no secret)"
  K create clients -r ai-agents -s clientId=agent-pki -s enabled=true -s publicClient=false \
    -s serviceAccountsEnabled=true -s standardFlowEnabled=false \
    -s clientAuthenticatorType=federated-jwt \
    -s 'attributes."jwt.credential.issuer"=spiffe' \
    -s "attributes.\"jwt.credential.sub\"=${TRUST_DOMAIN}/agent-pki"
fi
PKI_CID=$(client_id agent-pki)
K update "clients/$PKI_CID" -r ai-agents -s 'attributes."standard.token.exchange.enabled"=true'
say "standard token exchange enabled on agent-pki"

if has act-spiffe get "clients/$PKI_CID/protocol-mappers/models" -r ai-agents; then
  say "act-spiffe mapper attached to agent-pki"
else
  say "attaching act-spiffe mapper to agent-pki (nests the inbound act chain)"
  K create "clients/$PKI_CID/protocol-mappers/models" -r ai-agents \
    -s name=act-spiffe -s protocol=openid-connect -s protocolMapper=act-spiffe-mapper -s 'config={}'
fi

# ---- 2. audience carriers ---------------------------------------------------
# pki-audience: put on AGENT-CLIENT so its exchanged token is addressed to the
# PKI agent. cert-audience: put on AGENT-PKI so ITS exchanged token is addressed
# to the certificate service. Each agent can only address the next hop.
# Each hop needs TWO audience values, for two different checks:
#   - the canonical resource identifier, which the receiving RESOURCE SERVER
#     validates (the anti-passthrough rule, D-005);
#   - the receiving client's Keycloak clientId, because the exchange refuses
#     when the REQUESTER is not in the subject token's aud, and it matches
#     client.getClientId() literally (AbstractTokenExchangeProvider:245).
# Miss the second and hop 2 dies with "Client is not within the token audience".
make_audience_scope() { # $1 = scope name, $2 = resource URI, $3 = clientId or ""
  local sid; sid=$(scope_id "$1")
  if [ -n "$sid" ]; then say "client-scope $1 exists"; else
    say "creating client-scope $1 (aud=$2${3:+ + $3})"
    sid=$(K create client-scopes -r ai-agents -s name="$1" -s protocol=openid-connect -i)
    K create "client-scopes/$sid/protocol-mappers/models" -r ai-agents \
      -s name="$1-resource" -s protocol=openid-connect -s protocolMapper=oidc-audience-mapper \
      -s "config.\"included.custom.audience\"=$2" \
      -s 'config."access.token.claim"=true'
    if [ -n "$3" ]; then
      K create "client-scopes/$sid/protocol-mappers/models" -r ai-agents \
        -s name="$1-client" -s protocol=openid-connect -s protocolMapper=oidc-audience-mapper \
        -s "config.\"included.client.audience\"=$3" \
        -s 'config."access.token.claim"=true'
    fi
  fi
  printf '%s' "$sid"
}
# cert-service performs no exchange, so it needs no clientId audience.
PKI_AUD_SCOPE=$(make_audience_scope pki-audience "$PKI_RESOURCE" agent-pki)
CERT_AUD_SCOPE=$(make_audience_scope cert-audience "$CERT_RESOURCE" "")

AGENT_CID=$(client_id agent-client)
K update "clients/$AGENT_CID/default-client-scopes/$PKI_AUD_SCOPE" -r ai-agents
say "agent-client addresses the PKI agent (pki-audience default)"
K update "clients/$PKI_CID/default-client-scopes/$CERT_AUD_SCOPE" -r ai-agents
say "agent-pki addresses the certificate service (cert-audience default)"

# ---- 3. the two task scopes, assigned to exactly one agent each -------------
make_task_scope() { # $1 = scope name
  local sid; sid=$(scope_id "$1")
  if [ -n "$sid" ]; then say "client-scope $1 exists"; else
    say "creating task scope $1"
    sid=$(K create client-scopes -r ai-agents -s name="$1" -s protocol=openid-connect \
      -s 'attributes."include.in.token.scope"=true' -i)
  fi
  printf '%s' "$sid"
}
INITIATE_SCOPE=$(make_task_scope onboard:initiate)
ISSUE_SCOPE=$(make_task_scope issue:employee-cert)

# THE non-overlap. agent-client gets onboard:initiate and NOT issue:employee-cert;
# agent-pki gets the reverse. Adding the missing one to either client would let a
# single agent finish the task alone, which is the one thing this design forbids.
K update "clients/$AGENT_CID/optional-client-scopes/$INITIATE_SCOPE" -r ai-agents
say "agent-client may hold onboard:initiate"
K update "clients/$PKI_CID/optional-client-scopes/$ISSUE_SCOPE" -r ai-agents
say "agent-pki may hold issue:employee-cert"

# The human's clients must be able to GRANT both, or there is nothing to delegate.
for c in test-caller demo-web; do
  cid=$(client_id "$c")
  [ -n "$cid" ] || continue
  K update "clients/$cid/optional-client-scopes/$INITIATE_SCOPE" -r ai-agents
  K update "clients/$cid/optional-client-scopes/$ISSUE_SCOPE" -r ai-agents
  say "$c may request both task scopes (alice grants them at consent)"
done

# ---- 4. the delegation table (M13) -----------------------------------------
# Who may delegate to whom, carrying what, how deep. Keycloak has no concept of
# a delegation chain, so this table is the only place the chain's shape exists.
# Depth is read from the act chain, which only the AS ever writes, so a caller
# cannot pass off a third hop as a first one.
#
# The document is SINGLE-OWNER: the JSON lives in delegation-{profiles,policies}.json
# and is applied identically here and by setup-spiffe-idp.sh — kcadm replaces
# the whole document, so two scripts with their own variants meant whichever
# ran last silently deleted the other's executor (observed live).
K update realms/ai-agents/client-policies/profiles -r ai-agents -f - < keycloak/delegation-profiles.json >/dev/null
K update realms/ai-agents/client-policies/policies -r ai-agents -f - < keycloak/delegation-policies.json >/dev/null
has delegation-table get realms/ai-agents/client-policies/profiles -r ai-agents \
  || { echo "FATAL: delegation-table executor did not register — is the SPI jar current?"; exit 1; }
say "delegation table registered (agent-client -> agent-pki -> cert-service, depth 2)"

say "two-hop realm surface ready"
