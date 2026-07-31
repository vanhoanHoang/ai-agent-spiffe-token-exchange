#!/usr/bin/env bash
# Idempotent Keycloak "lab" realm for M4+ (kcadm.sh inside the container).
#   realm lab
#   user  alice / alice-password
#   client-scope mcp-audience: audience mapper -> https://mcp.lab.internal:8443 (D-005)
#   client test-caller     (public, direct-access grants, default scope mcp-audience)
#   client wrong-aud-client (confidential, service account, NO mcp audience) — the
#                           anti-passthrough test minting source
# NOTE: keycloak runs dev-file storage without a volume; container recreation wipes
# the realm. This script is cheap and idempotent — checks always re-run it.
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


K config credentials --server http://localhost:8080 --realm master --user admin --password admin

if K get realms/lab --fields realm >/dev/null 2>&1; then say "realm lab exists"; else
  say "creating realm lab"; K create realms -s realm=lab -s enabled=true
fi

if has alice get users -r lab -q username=alice --fields username; then
  say "user alice exists"
else
  say "creating user alice"
  K create users -r lab -s username=alice -s enabled=true
fi
ALICE_ID=$(K get users -r lab -q username=alice --fields id 2>/dev/null | tr -d ' \n' | sed 's/.*"id":"\([^"]*\)".*/\1/')
# Complete profile + no required actions, else password grant fails with
# "Account is not fully set up"
K update "users/$ALICE_ID" -r lab -s email=alice@lab.internal -s firstName=Alice \
  -s lastName=Lab -s emailVerified=true -s 'requiredActions=[]'
K set-password -r lab --username alice --new-password alice-password

SCOPE_ID=$(K get client-scopes -r lab --fields id,name 2>/dev/null | tr -d ' \n' | grep -o '{"id":"[^"]*","name":"mcp-audience"}' | sed 's/.*"id":"\([^"]*\)".*/\1/' || true)
if [ -n "$SCOPE_ID" ]; then say "client-scope mcp-audience exists ($SCOPE_ID)"; else
  say "creating client-scope mcp-audience"
  SCOPE_ID=$(K create client-scopes -r lab -s name=mcp-audience -s protocol=openid-connect -i)
  K create "client-scopes/$SCOPE_ID/protocol-mappers/models" -r lab \
    -s name=mcp-aud -s protocol=openid-connect -s protocolMapper=oidc-audience-mapper \
    -s 'config."included.custom.audience"=https://mcp.lab.internal:8443' \
    -s 'config."access.token.claim"=true'
fi

client_id() { K get clients -r lab -q clientId="$1" --fields id 2>/dev/null | tr -d ' \n' | sed 's/.*"id":"\([^"]*\)".*/\1/'; }

if has test-caller get clients -r lab -q clientId=test-caller --fields clientId; then
  say "client test-caller exists"
else
  say "creating client test-caller"
  K create clients -r lab -s clientId=test-caller -s publicClient=true \
    -s directAccessGrantsEnabled=true -s enabled=true
fi
CID=$(client_id test-caller)
K update "clients/$CID/default-client-scopes/$SCOPE_ID" -r lab
say "test-caller default scope mcp-audience attached"

if has wrong-aud-client get clients -r lab -q clientId=wrong-aud-client --fields clientId; then
  say "client wrong-aud-client exists"
else
  say "creating client wrong-aud-client (no mcp audience — anti-passthrough source)"
  K create clients -r lab -s clientId=wrong-aud-client -s publicClient=false \
    -s serviceAccountsEnabled=true -s secret=wrong-aud-secret -s enabled=true
fi

say "realm lab ready"
