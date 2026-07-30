#!/usr/bin/env bash
# M4 exit criterion (BUILD-PLAN M4):
#  1. curl with no token -> 401 carrying WWW-Authenticate with resource_metadata
#  2. curl /.well-known/oauth-protected-resource -> valid JSON pointing at Keycloak
#  3. curl with a token minted for a DIFFERENT audience -> rejected (anti-passthrough)
# Plus a positive control (right-audience token -> 200) to prove 3 is aud-specific.
set -euo pipefail
cd "$(dirname "$0")/.."
fail() { echo "M4 FAIL: $1"; exit 1; }

KC=http://localhost:8080
MCP=http://localhost:8443
RESOURCE_ID="https://mcp.lab.internal:8443"

(cd infra && docker compose up -d --wait --wait-timeout 240) >/dev/null || fail "stack not healthy"
bash infra/keycloak/setup-realm.sh >/dev/null

# -- 1. No token -> 401 + resource_metadata --------------------------------
code=$(curl -s -o /dev/null -w '%{http_code}' "$MCP/api/whoami")
[ "$code" = "401" ] || fail "no-token call returned $code, want 401"
hdr=$(curl -s -D - -o /dev/null "$MCP/api/whoami" | grep -i '^www-authenticate:')
echo "$hdr" | grep -q 'resource_metadata="' || fail "WWW-Authenticate lacks resource_metadata: $hdr"
echo "OK: 401 + WWW-Authenticate resource_metadata"

# -- 2. RFC 9728 metadata --------------------------------------------------
meta=$(curl -s "$MCP/.well-known/oauth-protected-resource")
echo "$meta" | grep -q "\"resource\"" || fail "metadata lacks resource: $meta"
echo "$meta" | grep -q "$RESOURCE_ID" || fail "metadata resource != $RESOURCE_ID: $meta"
echo "$meta" | grep -q "http://keycloak:8080/realms/lab" || fail "metadata does not point at Keycloak: $meta"
echo "OK: protected-resource metadata points at Keycloak"

# -- 3. Wrong-audience token -> rejected (the anti-passthrough test) -------
wrong=$(curl -s -d grant_type=client_credentials -d client_id=wrong-aud-client -d client_secret=wrong-aud-secret \
  "$KC/realms/lab/protocol/openid-connect/token" | sed 's/.*"access_token":"\([^"]*\)".*/\1/')
[ -n "$wrong" ] && [ "${#wrong}" -gt 100 ] || fail "could not obtain wrong-aud token"
code=$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $wrong" "$MCP/api/whoami")
[ "$code" = "401" ] || fail "wrong-audience token returned $code, want 401"
echo "OK: wrong-audience token rejected with 401"

# -- Control: right-audience token -> 200 ----------------------------------
good=$(curl -s -d grant_type=password -d client_id=test-caller -d username=alice -d password=alice-password \
  "$KC/realms/lab/protocol/openid-connect/token" | sed 's/.*"access_token":"\([^"]*\)".*/\1/')
[ -n "$good" ] && [ "${#good}" -gt 100 ] || fail "could not obtain right-aud token"
body=$(curl -s -w '\n%{http_code}' -H "Authorization: Bearer $good" "$MCP/api/whoami")
code=$(echo "$body" | tail -1)
[ "$code" = "200" ] || fail "right-audience token returned $code, want 200 (body: $body)"
echo "$body" | grep -q '"sub"' || fail "whoami response lacks sub"
echo "OK: right-audience token accepted (control)"

echo "M4 PASS"
