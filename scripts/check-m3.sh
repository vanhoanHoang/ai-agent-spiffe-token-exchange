#!/usr/bin/env bash
# M3 exit criterion (BUILD-PLAN M3), two commands plus obligations:
#  1. openssl verify: a FRESH SVID chains to the EJBCA root.
#  2. Negative test: a leaf with URI SAN outside spiffe://lab.internal/ signed by
#     the intermediate is REJECTED (with an in-domain positive control to prove
#     the rejection is the name constraint, not setup noise). Result -> D-002.
# Plus D-003 obligation: agent.conf no longer contains insecure_bootstrap.
set -euo pipefail
cd "$(dirname "$0")/.."
dkr() { MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker "$@"; }
fail() { echo "M3 FAIL: $1"; exit 1; }

PKI=infra/pki
# Relative temp dir: keeps every openssl file argument slash-free so
# MSYS_NO_PATHCONV (needed for -subj) can't break file resolution.
TMP=".m3tmp.$$"; mkdir -p "$TMP"
OUT_VOL=m3-svid-out
trap 'rm -rf "$TMP"; docker volume rm -f "$OUT_VOL" >/dev/null 2>&1 || true' EXIT

# -- 0. File contract (infra/pki/README.md) --------------------------------
for f in ejbca-root.pem spire-intermediate.pem spire-intermediate-key.pem chain.pem; do
  [ -f "$PKI/$f" ] || fail "contract file missing: $PKI/$f (run infra/pki/setup-ejbca.sh)"
done
# RFC 5280 URI constraints match the URI HOST — openssl renders "URI:lab.internal",
# which permits spiffe://lab.internal/* and nothing else.
openssl x509 -in "$PKI/spire-intermediate.pem" -noout -text | grep -A3 "Name Constraints" | grep -q "URI:lab.internal" \
  || fail "intermediate carries no URI name constraint for host lab.internal"

# -- D-003 obligation ------------------------------------------------------
grep -q "insecure_bootstrap" infra/spire/agent.conf && fail "insecure_bootstrap still present in agent.conf"
grep -q 'UpstreamAuthority "disk"' infra/spire/server.conf || fail "server.conf lacks disk UpstreamAuthority"

# -- 1. Fresh SVID chains to the EJBCA root --------------------------------
(cd infra && docker compose up -d --wait --wait-timeout 180) >/dev/null || fail "stack not healthy"
bash infra/spire/register-workloads.sh >/dev/null

ok=""
for i in $(seq 1 10); do
  docker volume rm -f "$OUT_VOL" >/dev/null 2>&1 || true
  if out=$(dkr run --rm --label org.lab.workload=agent-client \
      -v spiffe-mcp-lab_spire-agent-socket:/spire-sock:ro -v "$OUT_VOL":/out \
      --entrypoint /opt/spire/bin/spire-agent ghcr.io/spiffe/spire-agent:1.15.2 \
      api fetch x509 -socketPath /spire-sock/api.sock -write /out 2>&1) \
     && echo "$out" | grep -q "spiffe://lab.internal/agent-client"; then ok=1; break; fi
  sleep 3
done
[ -n "$ok" ] || fail "could not fetch SVID: $out"
dkr run --rm -v "$OUT_VOL":/out:ro busybox cat /out/svid.0.pem > "$TMP/svid-chain.pem"
dkr run --rm -v "$OUT_VOL":/out:ro busybox cat /out/bundle.0.pem > "$TMP/spire-bundle.pem"

# split: first cert = leaf, rest = intermediates presented by SPIRE
awk '/BEGIN CERT/{n++} n==1' "$TMP/svid-chain.pem" > "$TMP/leaf.pem"
awk '/BEGIN CERT/{n++} n>1'  "$TMP/svid-chain.pem" > "$TMP/presented.pem"
cat "$TMP/presented.pem" "$TMP/spire-bundle.pem" "$PKI/chain.pem" > "$TMP/untrusted.pem"

openssl verify -CAfile "$PKI/ejbca-root.pem" -untrusted "$TMP/untrusted.pem" "$TMP/leaf.pem" >/dev/null \
  || fail "fresh SVID does NOT chain to the EJBCA root"
echo "OK: fresh SVID chains to EJBCA root (trust anchor = ejbca-root.pem only)"

# -- 2. Negative test: issuance outside the trust domain -------------------
mk_leaf() { # $1=uri $2=name
  openssl ecparam -name prime256v1 -genkey -noout -out "$TMP/$2.key" 2>/dev/null
  MSYS_NO_PATHCONV=1 openssl req -new -key "$TMP/$2.key" -subj "/O=neg-test/CN=$2" -out "$TMP/$2.csr" 2>/dev/null
  printf "subjectAltName=URI:%s\nbasicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\n" "$1" > "$TMP/$2.ext"
  openssl x509 -req -in "$TMP/$2.csr" -CA "$PKI/spire-intermediate.pem" -CAkey "$PKI/spire-intermediate-key.pem" \
    -CAcreateserial -out "$TMP/$2.pem" -days 1 -extfile "$TMP/$2.ext" 2>/dev/null
}
mk_leaf "spiffe://lab.internal/neg-test-control" good
mk_leaf "spiffe://evil.example/impostor" evil

openssl verify -CAfile "$PKI/ejbca-root.pem" -untrusted "$PKI/chain.pem" "$TMP/good.pem" >/dev/null \
  || fail "positive control (in-domain URI) failed to verify — cannot trust the negative result"
if openssl verify -CAfile "$PKI/ejbca-root.pem" -untrusted "$PKI/chain.pem" "$TMP/evil.pem" >/dev/null 2>&1; then
  fail "VERIFIER DOES NOT ENFORCE URI NAME CONSTRAINTS: out-of-domain leaf verified (record in D-002)"
fi
echo "OK: openssl $(openssl version | cut -d' ' -f2) rejects out-of-domain URI, accepts in-domain control"

echo "M3 PASS"
