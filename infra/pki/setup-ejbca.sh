#!/usr/bin/env bash
# Automated EJBCA CA-hierarchy setup for M3 (re-runnable; human can execute solo).
#
#   EvidenRoot (ECDSA P-256, 10y, self-signed)
#     └── SpireIntermediate (ECDSA P-256, 2y, certificate profile
#         "spireIntermediateCA" = SUBCA clone + name constraints;
#         permittedSubtrees URI host = ai-agent.id.eviden.internal)
#
# EJBCA's fixed profiles (SUBCA, ...) are immutable and there is no CLI command
# to create a profile, so the profile is generated with EJBCA's OWN classes
# (CertificateProfile → XMLEncoder) inside the container and imported via
# `ca importprofiles`. RFC 5280 URI name constraints match the URI HOST, so the
# encoded constraint is "uniformResourceIdentifier:ai-agent.id.eviden.internal" and openssl
# renders it as "URI:ai-agent.id.eviden.internal" — that permits spiffe://ai-agent.id.eviden.internal/* only.
#
# Produces the infra/pki contract files (see README.md):
#   ejbca-root.pem, spire-intermediate.pem, spire-intermediate-key.pem, chain.pem
set -euo pipefail
cd "$(dirname "$0")"
FORCE="${1:-}"

EX()  { (cd .. && MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker compose exec -T ejbca /opt/keyfactor/bin/ejbca.sh "$@"); }
EXSH(){ (cd .. && MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker compose exec -T ejbca sh -c "$1"); }
CP()  { (cd .. && MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker compose cp "ejbca:$1" "pki/$2"); }
say() { echo "== $*"; }

have_files() { [ -f ejbca-root.pem ] && [ -f spire-intermediate.pem ] && [ -f spire-intermediate-key.pem ] && [ -f chain.pem ]; }

say "starting ejbca (compose profile pki)"
(cd .. && docker compose --profile pki up -d ejbca >/dev/null)
for i in $(seq 1 60); do EX ca listcas >/dev/null 2>&1 && break; sleep 5; done
EX ca listcas >/dev/null || { echo "EJBCA CLI not responding"; exit 1; }

ca_exists() { EX ca listcas 2>/dev/null | grep -q "CA Name: $1"; }

# Existence is not consistency: the contract files and the ejbca-data volume
# are one unit (files copied from another machine, or a volume recreated after
# this script ran). SPIRE and Keycloak trust ejbca-root.pem, so a mismatch is
# not patched here — it is reported with the runbook's resolution.
if [ "$FORCE" != "--force" ] && have_files; then
  if ca_exists EvidenRoot; then
    EX ca getcacert --caname EvidenRoot -f /tmp/evidenroot-live.pem >/dev/null
    mkdir -p ../.stage && CP /tmp/evidenroot-live.pem ../.stage/evidenroot-live.pem
    live=$(openssl x509 -in ../.stage/evidenroot-live.pem -noout -fingerprint -sha256); rm -f ../.stage/evidenroot-live.pem
    mine=$(openssl x509 -in ejbca-root.pem -noout -fingerprint -sha256)
    if [ "$live" = "$mine" ]; then
      say "contract files present and match the running EJBCA's EvidenRoot — nothing to do (use --force to re-export)"; exit 0
    fi
    echo "FATAL: infra/pki/ejbca-root.pem is not the EvidenRoot of the running EJBCA."
  else
    echo "FATAL: infra/pki contract files exist but the running EJBCA has no EvidenRoot."
  fi
  echo "The files and the ejbca-data volume come from different machines or runs. Resolution (docs/RUNBOOK-WIN11.md):"
  echo "  rm infra/pki/*.pem infra/pki/*.srl; rm -r infra/pki/ra infra/spire/bootstrap"
  echo "  docker volume rm spiffe-mcp-lab_ejbca-data"
  echo "  then re-run the three one-time scripts (demo\\setup-once.cmd)."
  exit 1
fi

# -- 1. Root CA ------------------------------------------------------------
if ca_exists EvidenRoot; then say "EvidenRoot exists"; else
  say "creating EvidenRoot"
  EX ca init --caname EvidenRoot --dn "CN=Eviden Root CA,O=eviden" \
     --tokenType soft --tokenPass null --keyspec prime256v1 --keytype ECDSA \
     -v 3650 --policy null -s SHA256withECDSA
fi
ROOT_ID=$(EX ca listcas 2>/dev/null | awk '/CA Name: EvidenRoot/{f=1;next} f&&/ Id: /{print $NF; exit}')
[ -n "$ROOT_ID" ] || { echo "cannot determine EvidenRoot CA ID"; exit 1; }
say "EvidenRoot id=$ROOT_ID"

# -- 2. Custom certificate profile with name constraints enabled -----------
if EX ca editcertificateprofile spireIntermediateCA --field useNameConstraints -getValue 2>/dev/null | grep -q "returned value 'true'"; then
  say "profile spireIntermediateCA exists"
else
  say "creating certificate profile spireIntermediateCA (SUBCA clone + NC) via EJBCA's own classes"
  EXSH 'cat > /tmp/GenProfile.java <<"JEOF"
import java.beans.XMLEncoder;
import java.io.FileOutputStream;
import java.util.ArrayList;
import java.util.List;
import org.cesecore.certificates.certificateprofile.CertificateProfile;
import org.cesecore.certificates.certificateprofile.CertificateProfileConstants;

public class GenProfile {
    public static void main(String[] args) throws Exception {
        CertificateProfile p = new CertificateProfile(CertificateProfileConstants.CERTPROFILE_FIXED_SUBCA);
        p.setUseNameConstraints(true);
        p.setNameConstraintsCritical(true);
        p.setAvailableCAs(new ArrayList<>(List.of(CertificateProfile.ANYCA)));
        try (XMLEncoder enc = new XMLEncoder(new FileOutputStream(args[0]))) {
            enc.writeObject(p.saveData());
        }
    }
}
JEOF
mkdir -p /tmp/profimport && java -cp "/opt/keyfactor/appserver/standalone/deployments/ejbca.ear/lib/*" \
  /tmp/GenProfile.java /tmp/profimport/certprofile_spireIntermediateCA-618304998.xml'
  EX ca importprofiles -d /tmp/profimport
fi

# -- 3. Intermediate CA ----------------------------------------------------
if ca_exists SpireIntermediate; then say "SpireIntermediate exists"; else
  say "creating SpireIntermediate (signed by EvidenRoot)"
  EX ca init --caname SpireIntermediate --dn "CN=SPIRE Intermediate CA,O=eviden" \
     --tokenType soft --tokenPass null --keyspec prime256v1 --keytype ECDSA \
     -v 730 --policy null -s SHA256withECDSA --signedby "$ROOT_ID"
fi
EX ca changecertprofile --caname SpireIntermediate --certprofile spireIntermediateCA
EX ca editca SpireIntermediate nameConstraintsPermitted "uniformResourceIdentifier:ai-agent.id.eviden.internal"

# -- 4. Signing key: generated LOCALLY, imported into EJBCA ---------------
# EJBCA soft tokens are non-exportable (exportca fails with
# PrivateKeyNotExtractableException), so the flow is inverted: the intermediate
# key is generated here (it must live on SPIRE's disk anyway, per the disk
# UpstreamAuthority contract), imported into the CA's crypto token, and the CA
# is re-pointed at it before re-issuance. The key never needs to leave EJBCA
# because it never existed only inside it.
if [ ! -f spire-intermediate-key.pem ]; then
  say "generating local intermediate signing key"
  openssl ecparam -name prime256v1 -genkey -noout -out spire-intermediate-key.pem
  chmod 600 spire-intermediate-key.pem
fi
if EX cryptotoken listkeys --token SpireIntermediate 2>/dev/null | grep -q spireExtSignKey; then
  say "spireExtSignKey already imported"
else
  say "importing local key into the SpireIntermediate crypto token"
  mkdir -p ../.stage
  openssl pkcs8 -topk8 -nocrypt -in spire-intermediate-key.pem -out ../.stage/spireint-pk8.pem
  openssl ec -in spire-intermediate-key.pem -pubout -out ../.stage/spireint-pub.pem 2>/dev/null
  (cd .. && MSYS_NO_PATHCONV=1 docker compose cp ./.stage/spireint-pk8.pem ejbca:/tmp/spireint-pk8.pem \
         && MSYS_NO_PATHCONV=1 docker compose cp ./.stage/spireint-pub.pem ejbca:/tmp/spireint-pub.pem)
  rm -rf ../.stage
  EX cryptotoken importkeypair --token SpireIntermediate --privkey-file /tmp/spireint-pk8.pem \
     --pubkey-file /tmp/spireint-pub.pem --alias spireExtSignKey --key-algorithm EC --auth-code null
  # docker compose cp writes as root; the ejbca user cannot rm those, so clean as root
  (cd .. && MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker compose exec -T -u 0 ejbca \
     sh -c 'rm -f /tmp/spireint-pk8.pem /tmp/spireint-pub.pem')
fi
printf "certSignKey spireExtSignKey\ncrlSignKey spireExtSignKey\nkeyEncryptKey encryptKey\ndefaultKey encryptKey\ntestKey signKey\n" > ../.catoken.props
(cd .. && MSYS_NO_PATHCONV=1 docker compose cp ./.catoken.props ejbca:/tmp/catoken.props)
rm ../.catoken.props
EX ca changecatoken --caname SpireIntermediate --cryptotoken SpireIntermediate --tokenprop /tmp/catoken.props --execute

# -- 5. Re-issue if needed, export contract files --------------------------
EX ca getcacert --caname SpireIntermediate -f /tmp/spireint.pem
CP /tmp/spireint.pem spire-intermediate.pem
LOCALPUB=$(openssl ec -in spire-intermediate-key.pem -pubout 2>/dev/null | openssl sha256 | cut -d' ' -f2)
CERTPUB=$(openssl x509 -in spire-intermediate.pem -noout -pubkey | openssl sha256 | cut -d' ' -f2)
if [ "$LOCALPUB" = "$CERTPUB" ] && openssl x509 -in spire-intermediate.pem -noout -text | grep -q "URI:ai-agent.id.eviden.internal"; then
  say "intermediate already bound to local key with name constraints"
else
  say "re-issuing intermediate (local key + name constraints)"
  EX ca renewca --caname SpireIntermediate
  EX ca getcacert --caname SpireIntermediate -f /tmp/spireint.pem
  CP /tmp/spireint.pem spire-intermediate.pem
fi
EX ca getcacert --caname EvidenRoot -f /tmp/evidenroot.pem
CP /tmp/evidenroot.pem ejbca-root.pem
cat spire-intermediate.pem ejbca-root.pem > chain.pem

# -- 5. Self-check ---------------------------------------------------------
openssl verify -CAfile ejbca-root.pem spire-intermediate.pem >/dev/null \
  || { echo "FATAL: intermediate does not verify against root"; exit 1; }
openssl x509 -in spire-intermediate.pem -noout -text | grep -q "URI:ai-agent.id.eviden.internal" \
  || { echo "FATAL: intermediate has no URI name constraint"; exit 1; }
KEYMOD=$(openssl ec -in spire-intermediate-key.pem -pubout 2>/dev/null | openssl sha256 | cut -d' ' -f2)
CERTMOD=$(openssl x509 -in spire-intermediate.pem -noout -pubkey | openssl sha256 | cut -d' ' -f2)
[ "$KEYMOD" = "$CERTMOD" ] || { echo "FATAL: exported key does not match intermediate cert"; exit 1; }
say "done. intermediate constraint:"
openssl x509 -in spire-intermediate.pem -noout -text | grep -A2 "Name Constraints"
