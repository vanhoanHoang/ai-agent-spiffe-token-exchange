#!/usr/bin/env bash
# M4 exit criterion (BUILD-PLAN M4):
#  1. call with no token -> 401 carrying WWW-Authenticate with resource_metadata
#  2. /.well-known/oauth-protected-resource -> valid JSON pointing at Keycloak
#  3. a token minted for a DIFFERENT audience -> rejected (anti-passthrough)
# Plus a positive control (right-audience token -> 200) to prove 3 is aud-specific.
# Transport note: since D-006 (M5) the server is mTLS-only (client-auth: need),
# so every probe presents the agent-client X509-SVID; the OAuth assertions are
# unchanged. -k because the server cert is an SVID (URI SAN), not a localhost cert.
set -euo pipefail
cd "$(dirname "$0")/.."
dkr() { MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker "$@"; }
fail() { echo "M4 FAIL: $1"; exit 1; }

KC=http://localhost:8080
MCP=https://localhost:8443
RESOURCE_ID="https://mcp.ai-agent.id.eviden.internal:8443"
AGENT_IMG=ghcr.io/spiffe/spire-agent:1.15.2   # pinned per docs/VERSIONS.md
SOCK_VOL=spiffe-mcp-lab_spire-agent-socket
OUT_VOL=m4-svid-out
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"; docker volume rm -f "$OUT_VOL" >/dev/null 2>&1 || true' EXIT

(cd infra && docker compose up -d --wait --wait-timeout 240) >/dev/null || fail "stack not healthy"
bash infra/spire/register-workloads.sh >/dev/null
bash infra/keycloak/setup-realm.sh >/dev/null

# Fetch the agent-client SVID so curl can pass the mTLS gate (the OAuth layer
# under test sits behind it).
ok=""
for i in $(seq 1 10); do
  docker volume rm -f "$OUT_VOL" >/dev/null 2>&1 || true
  if dkr run --rm --label org.lab.workload=agent-client \
      -v "$SOCK_VOL":/spire-sock:ro -v "$OUT_VOL":/out \
      --entrypoint /opt/spire/bin/spire-agent "$AGENT_IMG" \
      api fetch x509 -socketPath /spire-sock/api.sock -write /out >/dev/null 2>&1; then ok=1; break; fi
  sleep 3
done
[ -n "$ok" ] || fail "could not fetch agent-client SVID"
dkr run --rm -v "$OUT_VOL":/out:ro busybox cat /out/svid.0.pem > "$TMP/svid.pem"
dkr run --rm -v "$OUT_VOL":/out:ro busybox cat /out/svid.0.key > "$TMP/svid.key"
MCURL() { curl -sk --cert "$TMP/svid.pem" --key "$TMP/svid.key" "$@"; }

# -- 1. No token -> 401 + resource_metadata --------------------------------
code=$(MCURL -o /dev/null -w '%{http_code}' "$MCP/api/whoami")
[ "$code" = "401" ] || fail "no-token call returned $code, want 401"
hdr=$(MCURL -D - -o /dev/null "$MCP/api/whoami" | grep -i '^www-authenticate:')
echo "$hdr" | grep -q 'resource_metadata="' || fail "WWW-Authenticate lacks resource_metadata: $hdr"
echo "OK: 401 + WWW-Authenticate resource_metadata"

# -- 2. RFC 9728 metadata --------------------------------------------------
meta=$(MCURL "$MCP/.well-known/oauth-protected-resource")
echo "$meta" | grep -q "\"resource\"" || fail "metadata lacks resource: $meta"
echo "$meta" | grep -q "$RESOURCE_ID" || fail "metadata resource != $RESOURCE_ID: $meta"
echo "$meta" | grep -q "http://keycloak:8080/realms/ai-agents" || fail "metadata does not point at Keycloak: $meta"
echo "OK: protected-resource metadata points at Keycloak"

# -- 3. Wrong-audience token -> rejected (the anti-passthrough test) -------
wrong=$(curl -s -d grant_type=client_credentials -d client_id=wrong-aud-client -d client_secret=wrong-aud-secret \
  "$KC/realms/ai-agents/protocol/openid-connect/token" | sed 's/.*"access_token":"\([^"]*\)".*/\1/')
[ -n "$wrong" ] && [ "${#wrong}" -gt 100 ] || fail "could not obtain wrong-aud token"
code=$(MCURL -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $wrong" "$MCP/api/whoami")
[ "$code" = "401" ] || fail "wrong-audience token returned $code, want 401"
echo "OK: wrong-audience token rejected with 401"

# -- Control: right-audience token -> 200 ----------------------------------
good=$(curl -s -d grant_type=password -d client_id=test-caller -d username=alice -d password=alice-password \
  "$KC/realms/ai-agents/protocol/openid-connect/token" | sed 's/.*"access_token":"\([^"]*\)".*/\1/')
[ -n "$good" ] && [ "${#good}" -gt 100 ] || fail "could not obtain right-aud token"
body=$(MCURL -w '\n%{http_code}' -H "Authorization: Bearer $good" "$MCP/api/whoami")
code=$(echo "$body" | tail -1)
[ "$code" = "200" ] || fail "right-audience token returned $code, want 200 (body: $body)"
echo "$body" | grep -q '"sub"' || fail "whoami response lacks sub"
echo "OK: right-audience token accepted (control)"

echo "M4 PASS"
