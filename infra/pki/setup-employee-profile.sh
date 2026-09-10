#!/usr/bin/env bash
# M12: EJBCA employee-issuance surface (re-runnable; human executes solo — CLAUDE.md §7).
#
# Creates, against the EXISTING hierarchy (never touches CAs or their keys):
#   - REST Certificate Management protocol: enabled (9.3.7 default: disabled)
#   - certificate profile  "employeeDevice"  (ENDUSER clone, generated with
#     EJBCA's own classes — same technique as setup-ejbca.sh, there is no CLI
#     command to create a profile)
#   - end-entity profile   "employeeDevice"  (EvidenRoot only, employeeDevice only)
#   - RA identity for cert-service: end entity ra-cert-service on ManagementCA,
#     P12 batch-generated, role "Cert Service RA" with the minimal rule set
#     (modeled on the container's Public Access Role, read from this instance)
#
# EJBCA 9.3.7's REST API authenticates every call (verified: plain 8080 → 302,
# 8443 without client cert → 403). cert-service therefore enrolls as this RA
# over mTLS. The 8443 server cert is minted per container hostname, so compose
# pins `hostname: ejbca` — this script verifies the SAN before exporting trust.
#
# Produces (consumed via the infra/pki/ra/ mount in docker-compose.yml):
#   pki/ra/ra-cert-service.p12   RA client keystore (gitignored, *.p12)
#   pki/ra/ejbca-tls-ca.pem      ManagementCA cert = TLS trust anchor for 8443
set -euo pipefail
cd "$(dirname "$0")"
FORCE="${1:-}"
RAPW="${EJBCA_RA_PASSWORD:-enroll-lab}"

EX()  { (cd .. && MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker compose exec -T ejbca /opt/keyfactor/bin/ejbca.sh "$@"); }
EXSH(){ (cd .. && MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker compose exec -T ejbca sh -c "$1"); }
CP()  { (cd .. && MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker compose cp "ejbca:$1" "pki/$2"); }
say() { echo "== $*"; }

say "starting ejbca (compose profile pki)"
(cd .. && docker compose --profile pki up -d ejbca >/dev/null)
for i in $(seq 1 60); do EX ca listcas >/dev/null 2>&1 && break; sleep 5; done
EX ca listcas >/dev/null || { echo "EJBCA CLI not responding"; exit 1; }

# Existence is not consistency. The RA keystore and the ejbca-data volume are
# one unit: pki/ra/ copied from another machine, or a volume recreated after
# this script ran, passes every "file exists" check and then kills hop 2 on
# stage ("HTTP/1.1 header parser received no bytes" — EJBCA closes the TLS
# connection on a client certificate its ManagementCA never issued). So the
# early exit requires the files to match the EJBCA that is running NOW.
if [ "$FORCE" != "--force" ] && [ -f ra/ra-cert-service.p12 ] && [ -f ra/ejbca-tls-ca.pem ]; then
  EX ca getcacert --caname ManagementCA -f /tmp/mgmtca-live.pem >/dev/null
  mkdir -p ../.stage && CP /tmp/mgmtca-live.pem ../.stage/mgmtca-live.pem
  live=$(openssl x509 -in ../.stage/mgmtca-live.pem -noout -fingerprint -sha256); rm -f ../.stage/mgmtca-live.pem
  mine=$(openssl x509 -in ra/ejbca-tls-ca.pem -noout -fingerprint -sha256)
  if [ "$live" != "$mine" ]; then
    say "RA credential present but pki/ra/ejbca-tls-ca.pem is NOT the ManagementCA of the running EJBCA — re-creating"
  elif ! openssl pkcs12 -in ra/ra-cert-service.p12 -passin "pass:$RAPW" -clcerts -nokeys 2>/dev/null \
         | openssl verify -CAfile ra/ejbca-tls-ca.pem >/dev/null 2>&1; then
    say "RA credential present but ra-cert-service.p12 was not issued by the running ManagementCA (or expired) — re-creating"
  else
    # Chain-valid is not accepted. On the company laptop a P12 that passed both
    # checks above was still refused by EJBCA at the TLS layer (closed
    # connection, root cause not established); a forced re-issue fixed it. So
    # the early exit needs EJBCA's own verdict: the REST status call over mTLS
    # with this P12, exactly what cert-service does. Wait for 8443 first.
    for i in $(seq 1 30); do
      echo | openssl s_client -connect localhost:8444 2>/dev/null | grep -q "BEGIN CERTIFICATE" && break; sleep 5
    done
    code=$(MSYS_NO_PATHCONV=1 curl -s -o /dev/null --max-time 15 --cert-type P12 --cert "ra/ra-cert-service.p12:$RAPW" \
             --cacert ra/ejbca-tls-ca.pem --resolve ejbca:8444:127.0.0.1 -w '%{http_code}' \
             https://ejbca:8444/ejbca/ejbca-rest-api/v1/certificate/status 2>/dev/null || true)
    if [ "$code" = 200 ]; then
      say "RA credential present and ACCEPTED by the running EJBCA (REST status 200 over mTLS) — nothing to do (use --force to re-create)"; exit 0
    fi
    say "RA credential present and chain-valid, but EJBCA refuses it over mTLS (HTTP '${code:-none}') — re-creating"
  fi
fi

# -- 0. TLS server identity must be the stable name --------------------------
# Wait for the TLS port too (the appserver opens it after the CLI DB is usable).
for i in $(seq 1 30); do
  SAN=$(echo | openssl s_client -connect localhost:8444 2>/dev/null | openssl x509 -noout -ext subjectAltName 2>/dev/null || true)
  [ -n "$SAN" ] && break; sleep 5
done
echo "$SAN" | grep -q "DNS:ejbca" || {
  echo "FATAL: 8443 cert SAN is '$SAN', not DNS:ejbca."
  echo "compose must set 'hostname: ejbca' on the ejbca service (then recreate the container so init mints the keystore)."
  exit 1
}
say "TLS server cert SAN verified: DNS:ejbca"

# -- 0b. WildFly truststore must not be empty --------------------------------
# Observed on this instance (9.3.7): recreating the container races the init's
# `ca createtruststore` against the DB, leaving a 32-byte EMPTY truststore.jks.
# Every TLS client cert is then rejected as a silent connection close, with
# nothing in the application log. Rebuild in place and reload when detected.
TS=/opt/keyfactor/appserver/standalone/configuration/truststore.jks
TS_SIZE=$(EXSH "stat -c %s $TS" | tr -d '[:space:]')
if [ "${TS_SIZE:-0}" -lt 100 ]; then
  say "truststore.jks is empty (container-recreation init race) — rebuilding"
  TS_PW=$(EXSH "awk '/name=\"httpsTS\"/{f=1} f&&/clear-text/{gsub(/.*clear-text=\"|\".*/,\"\"); print; exit}' /opt/keyfactor/appserver/standalone/configuration/standalone.xml" | tr -d '[:space:]')
  [ -n "$TS_PW" ] || { echo "FATAL: cannot read truststore password from standalone.xml"; exit 1; }
  EX ca createtruststore --format JKS --password "$TS_PW" --truststore "$TS" >/dev/null
  EXSH '/opt/keyfactor/appserver/bin/jboss-cli.sh --connect ":reload"' >/dev/null
  for i in $(seq 1 60); do
    EXSH 'curl -sf http://localhost:8080/ejbca/publicweb/healthcheck/ejbcahealth' 2>/dev/null | grep -q ALLOK && break
    sleep 5
  done
  say "truststore rebuilt and server reloaded"
fi

# -- 1. REST protocol --------------------------------------------------------
EX config protocols enable --name "REST Certificate Management" >/dev/null
say "REST Certificate Management enabled"

# -- 2. employeeDevice certificate profile (ENDUSER clone) -------------------
if EX ca editcertificateprofile employeeDevice --field description -getValue >/dev/null 2>&1; then
  say "certificate profile employeeDevice exists"
else
  say "creating certificate profile employeeDevice via EJBCA's own classes"
  EXSH 'cat > /tmp/GenEmployeeProfile.java <<"JEOF"
import java.beans.XMLEncoder;
import java.io.FileOutputStream;
import java.util.ArrayList;
import java.util.List;
import org.cesecore.certificates.certificateprofile.CertificateProfile;
import org.cesecore.certificates.certificateprofile.CertificateProfileConstants;

public class GenEmployeeProfile {
    public static void main(String[] args) throws Exception {
        CertificateProfile p = new CertificateProfile(CertificateProfileConstants.CERTPROFILE_FIXED_ENDUSER);
        p.setAvailableCAs(new ArrayList<>(List.of(CertificateProfile.ANYCA)));
        try (XMLEncoder enc = new XMLEncoder(new FileOutputStream(args[0]))) {
            enc.writeObject(p.saveData());
        }
    }
}
JEOF
mkdir -p /tmp/empimport && java -cp "/opt/keyfactor/appserver/standalone/deployments/ejbca.ear/lib/*" \
  /tmp/GenEmployeeProfile.java /tmp/empimport/certprofile_employeeDevice-618305000.xml'
  EX ca importprofiles -d /tmp/empimport
fi

# -- 3. employeeDevice end-entity profile ------------------------------------
ROOT_ID=$(EX ca listcas 2>/dev/null | awk '/CA Name: EvidenRoot/{f=1;next} f&&/ Id: /{print $NF; exit}')
[ -n "$ROOT_ID" ] || { echo "cannot determine EvidenRoot CA ID"; exit 1; }
CERTPROF_ID=$(EX ca editcertificateprofile employeeDevice --field certificateProfileId -getValue 2>/dev/null \
  | grep -o "returned value '[0-9]*'" | grep -o '[0-9]*' || true)
CERTPROF_ID="${CERTPROF_ID:-618305000}"
# changerule --help enumerates /endentityprofilesrules/<name>/ for every existing
# EE profile — the only CLI-visible existence probe (no list command in 9.3.7).
if EX roles changerule --help 2>&1 | grep -q "/endentityprofilesrules/employeeDevice/"; then
  say "end-entity profile employeeDevice exists"
else
  say "creating end-entity profile employeeDevice (CA=EvidenRoot id=$ROOT_ID, certprofile id=$CERTPROF_ID)"
  EXSH 'mkdir -p /tmp/gen-ee && cat > /tmp/gen-ee/GenEeProfile.java <<"JEOF"
import java.beans.XMLEncoder;
import java.io.FileOutputStream;
import java.util.List;
import org.ejbca.core.model.ra.raadmin.EndEntityProfile;

public class GenEeProfile {
    public static void main(String[] args) throws Exception {
        int caId = Integer.parseInt(args[1]);
        int certProfileId = Integer.parseInt(args[2]);
        EndEntityProfile p = new EndEntityProfile(true);
        p.setAvailableCAs(List.of(caId));
        p.setDefaultCA(caId);
        p.setAvailableCertificateProfileIds(List.of(certProfileId));
        p.setDefaultCertificateProfile(certProfileId);
        try (XMLEncoder enc = new XMLEncoder(new FileOutputStream(args[0]))) {
            enc.writeObject(p.saveData());
        }
    }
}
JEOF
mkdir -p /tmp/eeimport && java -cp "/opt/keyfactor/appserver/standalone/deployments/ejbca.ear/lib/*" \
  /tmp/gen-ee/GenEeProfile.java /tmp/eeimport/entityprofile_employeeDevice-618305001.xml '"$ROOT_ID $CERTPROF_ID"
  EX ca importprofiles -d /tmp/eeimport
fi

# -- 4. RA identity for cert-service ----------------------------------------
if EX ra setclearpwd --username ra-cert-service --password "$RAPW" >/dev/null 2>&1; then
  say "end entity ra-cert-service exists — resetting status to NEW so batch issues a fresh keystore"
  # Status stays GENERATED (40) after the first batch, and `batch` then generates
  # nothing (verified live: findendentity → Status: 40). NEW=10 per `setendentitystatus --help`.
  EX ra setendentitystatus --username ra-cert-service -S 10 >/dev/null
else
  say "creating RA end entity ra-cert-service (ManagementCA)"
  EX ra addendentity --username ra-cert-service --dn "CN=ra-cert-service,O=eviden" \
     --caname ManagementCA --type 1 --token P12 --password "$RAPW"
  EX ra setclearpwd --username ra-cert-service --password "$RAPW"
fi
say "batch-generating RA keystore"
EXSH 'mkdir -p /tmp/rabatch'
EX batch ra-cert-service -dir /tmp/rabatch
mkdir -p ra
CP /tmp/rabatch/ra-cert-service.p12 ra/ra-cert-service.p12

# -- 5. Role: minimal RA rights (modeled on the Public Access Role rules) ----
has_role() { EX roles listroles 2>/dev/null | grep -q "'Cert Service RA'"; }
if has_role; then say "role Cert Service RA exists"; else
  say "creating role Cert Service RA"
  EX roles addrole --role "Cert Service RA"
fi
for RULE in "/administrator/" "/ca/EvidenRoot/" \
            "/ca_functionality/create_certificate/" "/ca_functionality/view_ca/" \
            "/ca_functionality/use_username/" \
            "/ra_functionality/create_end_entity/" "/ra_functionality/edit_end_entity/" \
            "/ra_functionality/view_end_entity/" \
            "/endentityprofilesrules/employeeDevice/"; do
  EX roles changerule --name "Cert Service RA" --rule "$RULE" --state ACCEPT >/dev/null
done
MEMBERS=$(EX roles listadmins --role "Cert Service RA" 2>/dev/null || true)
if echo "$MEMBERS" | grep -q "ra-cert-service"; then
  say "role member exists"
else
  EX roles addrolemember --role "Cert Service RA" --caname ManagementCA \
     --with WITH_COMMONNAME --value ra-cert-service \
     --description "cert-service RA credential (M12)"
fi

# -- 6. TLS trust anchor for the client --------------------------------------
EX ca getcacert --caname ManagementCA -f /tmp/mgmtca.pem
CP /tmp/mgmtca.pem ra/ejbca-tls-ca.pem

# -- 7. Self-check -----------------------------------------------------------
[ -s ra/ra-cert-service.p12 ] || { echo "FATAL: RA keystore missing/empty"; exit 1; }
openssl x509 -in ra/ejbca-tls-ca.pem -noout -subject | grep -q ManagementCA \
  || { echo "FATAL: exported TLS anchor is not ManagementCA"; exit 1; }
openssl pkcs12 -in ra/ra-cert-service.p12 -passin "pass:$RAPW" -nokeys 2>/dev/null \
  | openssl x509 -noout -subject | grep -q "ra-cert-service" \
  || { echo "FATAL: RA keystore does not open with the expected password / subject"; exit 1; }
say "done. cert-service can now enroll. If it already attempted an issuance, restart it and agent-pki (the RA client and the MCP session are cached):"
say "  docker compose -f infra/docker-compose.yml restart cert-service agent-pki"
say "  pki/ra/ra-cert-service.p12 + pki/ra/ejbca-tls-ca.pem"
