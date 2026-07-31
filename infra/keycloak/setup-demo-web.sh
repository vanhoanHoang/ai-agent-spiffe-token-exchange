#!/usr/bin/env bash
# M10 P2.5: the browser-facing client. alice logs in HERE (authorization code
# + PKCE, public — no secret) and CONSENTS; the token this login mints is the
# subject token the agent exchanges per message.
#   consentRequired=true      -> the consent screen is the delegation moment
#   default scope agent-audience -> aud=agent-client, or the exchange refuses
#                                   (D-008 subject-token rule)
#   optional scope mcp:audit  -> the P3 toggle: withhold it and the audit tool
#                                is refused; grant it and the same ask succeeds
set -euo pipefail
cd "$(dirname "$0")/.."

K() { MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh "$@"; }
say() { echo "== $*"; }
# SIGPIPE-safe existence test (D-011): capture first, match second.
has() { # has <pattern> <kcadm args...>
  local pattern="$1"; shift
  local out
  out=$(K "$@" 2>/dev/null) || return 1
  printf '%s' "$out" | grep -q -- "$pattern"
}

scope_id() { K get client-scopes -r ai-agents --fields id,name 2>/dev/null | tr -d ' \n' | grep -o "{\"id\":\"[^\"]*\",\"name\":\"$1\"}" | sed 's/.*"id":"\([^"]*\)".*/\1/'; }

K config credentials --server http://localhost:8080 --realm master --user admin --password admin

if has demo-web get clients -r ai-agents -q clientId=demo-web --fields clientId; then
  say "client demo-web exists"
else
  say "creating client demo-web (public, PKCE S256, consent required)"
  K create clients -r ai-agents -s clientId=demo-web -s enabled=true \
    -s publicClient=true -s standardFlowEnabled=true -s consentRequired=true \
    -s 'attributes."pkce.code.challenge.method"=S256' \
    -s 'redirectUris=["http://localhost:8090/*"]'
fi

CID=$(K get clients -r ai-agents -q clientId=demo-web --fields id 2>/dev/null | tr -d ' \n' | sed 's/.*"id":"\([^"]*\)".*/\1/')

AG=$(scope_id agent-audience)
[ -n "$AG" ] || { echo "FATAL: agent-audience scope missing — run setup-spiffe-idp.sh first"; exit 1; }
K update "clients/$CID/default-client-scopes/$AG" -r ai-agents
say "demo-web default scope agent-audience attached (aud=agent-client)"

AUD=$(scope_id mcp:audit)
[ -n "$AUD" ] || { echo "FATAL: mcp:audit scope missing — run setup-spiffe-idp.sh first"; exit 1; }
K update "clients/$CID/optional-client-scopes/$AUD" -r ai-agents
say "demo-web optional scope mcp:audit attached (P3 consent toggle)"

say "demo-web ready"
