#!/usr/bin/env bash
# M2 exit criterion (BUILD-PLAN M2): spire-agent api fetch x509 returns a valid
# SVID with the expected SPIFFE ID for both workloads (agent-client, mcp-server),
# attested via docker label selectors through the shared Workload API socket.
set -euo pipefail
cd "$(dirname "$0")/.."

# Disable Git-Bash path mangling ONLY for docker calls (container paths must pass
# verbatim); host-side openssl still needs MSYS /tmp conversion to work.
dkr() { MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker "$@"; }

AGENT_IMG=ghcr.io/spiffe/spire-agent:1.15.2   # pinned per docs/VERSIONS.md
SOCK_VOL=spiffe-mcp-lab_spire-agent-socket
OUT_VOL=m2-svid-out
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"; docker volume rm -f "$OUT_VOL" >/dev/null 2>&1 || true' EXIT
fetch_svid() { # $1=workload label
  dkr run --rm --label org.lab.workload="$1" \
    -v "$SOCK_VOL":/spire-sock:ro -v "$OUT_VOL":/out \
    --entrypoint /opt/spire/bin/spire-agent "$AGENT_IMG" \
    api fetch x509 -socketPath /spire-sock/api.sock -write /out 2>&1
}
fail() { echo "M2 FAIL: $1"; exit 1; }

(cd infra && docker compose up -d --wait --wait-timeout 180) >/dev/null || fail "stack not healthy"
bash infra/spire/register-workloads.sh

(cd infra && MSYS_NO_PATHCONV=1 docker compose exec -T spire-server /opt/spire/bin/spire-server bundle show -format pem) > "$TMP/bundle.pem"
grep -q "BEGIN CERTIFICATE" "$TMP/bundle.pem" || fail "could not fetch trust bundle"

for w in agent-client mcp-server; do
  ok=""
  for i in $(seq 1 10); do   # entries take a few seconds to sync to the agent
    docker volume rm -f "$OUT_VOL" >/dev/null 2>&1 || true
    if out=$(fetch_svid "$w") && echo "$out" | grep -q "spiffe://ai-agent.id.eviden.internal/$w"; then ok=1; break; fi
    sleep 3
  done
  [ -n "$ok" ] || fail "no SVID for $w after retries; last output: $out"

  dkr run --rm -v "$OUT_VOL":/out:ro busybox cat /out/svid.0.pem > "$TMP/$w.pem"
  openssl x509 -in "$TMP/$w.pem" -noout -ext subjectAltName | grep -q "spiffe://ai-agent.id.eviden.internal/$w" \
    || fail "$w SVID URI SAN mismatch"
  # svid.0.pem = leaf + intermediates (X509-SVID chain); the bundle holds only
  # trust anchors. Verify the leaf with the delivered intermediates as untrusted
  # links — the previous leaf-vs-bundle verify only passed while a legacy
  # self-signed SPIRE CA still sat in the old datastore's bundle.
  rm -f "$TMP/leaf.pem" "$TMP/inter.pem"
  awk -v dir="$TMP" '/-----BEGIN CERTIFICATE-----/{n++} n==1{print > (dir"/leaf.pem")} n>1{print > (dir"/inter.pem")}' "$TMP/$w.pem"
  if [ -s "$TMP/inter.pem" ]; then
    openssl verify -CAfile "$TMP/bundle.pem" -untrusted "$TMP/inter.pem" "$TMP/leaf.pem" >/dev/null \
      || fail "$w SVID does not chain to the trust bundle"
  else
    openssl verify -CAfile "$TMP/bundle.pem" "$TMP/leaf.pem" >/dev/null \
      || fail "$w SVID does not chain to the trust bundle"
  fi
  echo "OK: $w -> spiffe://ai-agent.id.eviden.internal/$w (SAN + chain verified)"
done

echo "M2 PASS: both workloads receive valid SVIDs with expected SPIFFE IDs"
