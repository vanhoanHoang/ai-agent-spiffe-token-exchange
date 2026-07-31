#!/usr/bin/env bash
# D-002 (JDK row): does JDK PKIX path validation enforce the URI name constraint
# on the EJBCA intermediate? Mints an in-domain and an out-of-domain leaf with the
# intermediate key (same technique as check-m3.sh), then validates both chains
# with java.security.cert.CertPathValidator inside the pinned JDK-21 image.
set -euo pipefail
cd "$(dirname "$0")/.."
dkr() { MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker "$@"; }

PKI=infra/pki
TMP=".nctmp.$$"; mkdir -p "$TMP"
VOL=nc-test-vol
trap 'rm -rf "$TMP"; docker volume rm -f "$VOL" >/dev/null 2>&1 || true' EXIT

mk_leaf() { # $1=uri $2=name
  openssl ecparam -name prime256v1 -genkey -noout -out "$TMP/$2.key" 2>/dev/null
  MSYS_NO_PATHCONV=1 openssl req -new -key "$TMP/$2.key" -subj "/O=nc-test/CN=$2" -out "$TMP/$2.csr" 2>/dev/null
  printf "subjectAltName=URI:%s\nbasicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\n" "$1" > "$TMP/$2.ext"
  openssl x509 -req -in "$TMP/$2.csr" -CA "$PKI/spire-intermediate.pem" -CAkey "$PKI/spire-intermediate-key.pem" \
    -CAcreateserial -out "$TMP/$2.pem" -days 1 -extfile "$TMP/$2.ext" 2>/dev/null
}
mk_leaf "spiffe://ai-agent.id.eviden.internal/nc-control" good
mk_leaf "spiffe://evil.example/impostor" evil

cat > "$TMP/NcTest.java" <<'JEOF'
import java.io.FileInputStream;
import java.io.InputStream;
import java.security.cert.*;
import java.util.List;
import java.util.Set;

public class NcTest {
    public static void main(String[] args) throws Exception {
        CertificateFactory cf = CertificateFactory.getInstance("X.509");
        X509Certificate root = load(cf, args[0]);
        X509Certificate inter = load(cf, args[1]);
        X509Certificate leaf = load(cf, args[2]);
        CertPath path = cf.generateCertPath(List.of(leaf, inter));
        PKIXParameters params = new PKIXParameters(Set.of(new TrustAnchor(root, null)));
        params.setRevocationEnabled(false);
        try {
            CertPathValidator.getInstance("PKIX").validate(path, params);
            System.out.println("ACCEPT");
        } catch (CertPathValidatorException e) {
            System.out.println("REJECT: " + e.getMessage());
        }
    }

    static X509Certificate load(CertificateFactory cf, String p) throws Exception {
        try (InputStream in = new FileInputStream(p)) {
            return (X509Certificate) cf.generateCertificate(in);
        }
    }
}
JEOF

docker volume rm -f "$VOL" >/dev/null 2>&1 || true
for f in "$PKI/ejbca-root.pem" "$PKI/spire-intermediate.pem" "$TMP/good.pem" "$TMP/evil.pem" "$TMP/NcTest.java"; do
  dkr run --rm -i -v "$VOL":/w busybox sh -c "cat > /w/$(basename "$f")" < "$f"
done

run_jdk() { dkr run --rm -v "$VOL":/w maven:3.9-eclipse-temurin-21 \
  java /w/NcTest.java /w/ejbca-root.pem /w/spire-intermediate.pem "/w/$1"; }

echo "JDK $(dkr run --rm maven:3.9-eclipse-temurin-21 java -version 2>&1 | head -1)"
good=$(run_jdk good.pem); echo "in-domain control:  $good"
evil=$(run_jdk evil.pem); echo "out-of-domain leaf: $evil"

case "$good" in ACCEPT*) ;; *) echo "FAIL: control not accepted — result unusable"; exit 1;; esac
case "$evil" in REJECT*) echo "JDK PKIX ENFORCES URI name constraints"; exit 0;;
             *) echo "JDK PKIX DOES NOT ENFORCE URI name constraints"; exit 1;; esac
