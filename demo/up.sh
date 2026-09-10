#!/usr/bin/env bash
# One-command launch: preflight -> reset --full -> checklist --full.
# Same command on a fresh machine, after a reboot, or after a `down`.
#   --check : preflight only, touch nothing.
#
# The preflight encodes the launch failures actually seen in the field:
#   - a foreign stack holding one of our host ports ("port is already allocated"
#     halfway through compose up, stack left partially created);
#   - the one-time gitignored artifacts missing on a fresh machine (obscure
#     SPIRE/Keycloak/EJBCA errors much later);
#   - bare `docker compose up` after a `down` (volume-less Keycloak realm gone,
#     agent-web crashloops with "Realm does not exist") — avoided here by always
#     going through reset.sh, which re-runs the idempotent realm setup.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=../infra/llm-env.sh
. infra/llm-env.sh

fail=0
say() { printf '%-60s %s\n' "$1" "$2"; }
ok()  { say "$1" "OK"; }
bad() { say "$1" "FAIL — $2"; fail=1; }

# 0. The shell itself. On Windows `bash` resolves to WSL's bash.exe from
#    PowerShell/cmd (C:\Windows\System32\bash.exe): docker, paths and the
#    MSYS path conversion all differ, and nothing below would behave. The
#    scripts are written for Git Bash (MSYS). Fail before touching anything.
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*) ok "shell: Git Bash (MSYS)" ;;
  Linux)
    if [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/version 2>/dev/null; then
      say "shell" "FAIL — this is WSL bash. Open the 'Git Bash' app and run: bash demo/up.sh"; echo; exit 1
    fi; ok "shell: bash on Linux" ;;
  Darwin) ok "shell: bash on macOS" ;;
  *) ok "shell: $(uname -s)" ;;
esac
case "$PWD" in
  *'&'*) say "repo path" "WARN — '$PWD' contains '&'; docker is fine with it, host npm builds are not. Prefer C:\\lab\\spiffe-mcp-lab on a new machine" ;;
  *) ok "repo path has no '&'" ;;
esac
for t in docker curl openssl; do
  command -v "$t" >/dev/null 2>&1 && ok "tool: $t" || bad "tool: $t" "not on PATH (Git for Windows ships curl+openssl; Docker Desktop ships docker)"
done
# python is only needed by scripts/check-*.sh and demo/capture-run.sh, not by
# the launch itself. Windows 11 ships a Store STUB named python that opens the
# Store instead of running — detect that, warn only.
if out=$(python -c 'print(1)' 2>/dev/null) && [ "$out" = 1 ]; then ok "tool: python (check scripts)"
else say "tool: python" "MISSING or Store stub — only scripts/check-*.sh need it; install from python.org if you want them"; fi

# 1. Docker daemon.
if docker info >/dev/null 2>&1; then ok "docker daemon answering"
else say "docker daemon" "FAIL — start Docker Desktop first"; echo; exit 1; fi
mem=$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo 0)
if [ "${mem:-0}" -ge 5000000000 ]; then ok "docker memory $(( mem / 1073741824 )) GiB"
else bad "docker memory" "$(( mem / 1073741824 )) GiB — the stack idles at ~2.5 GiB and EJBCA init peaks higher; set memory=6GB in %USERPROFILE%\\.wslconfig (template: infra/wslconfig.example), then: wsl --shutdown, restart Docker Desktop"; fi

# 2. Host ports this stack binds: 8080 keycloak, 8083+8444 ejbca, 8090
#    agent-web, 8443 mcp-server. Our own containers are fine (reset.sh cycles
#    them); anything else must be stopped first.
for p in 8080 8083 8090 8443 8444; do
  holder=$(docker ps --format '{{.Names}} {{.Ports}}' \
           | awk -v pat=":${p}->" 'index($0, pat) {print $1; exit}')
  if [ -n "$holder" ]; then
    case "$holder" in
      spiffe-mcp-lab-*) ok "port $p (our own $holder)" ;;
      *) bad "port $p" "held by '$holder' — docker stop $holder" ;;
    esac
  elif netstat -an 2>/dev/null | grep -Eq "[:.]${p}[[:space:]].*(LISTEN|LISTENING)"; then
    bad "port $p" "a non-docker process is listening (Windows: netstat -ano | findstr :$p)"
  else
    ok "port $p free"
  fi
done
# Windows reserves whole port ranges for Hyper-V/WSL NAT; nothing listens, yet
# a bind fails with "access a socket in a way forbidden by its access
# permissions". Invisible to netstat; only netsh shows it.
if command -v netsh.exe >/dev/null 2>&1; then
  ranges=$(netsh.exe interface ipv4 show excludedportrange protocol=tcp 2>/dev/null | grep -oE '^ *[0-9]+ +[0-9]+' || true)
  for p in 8080 8083 8090 8443 8444; do
    hit=$(echo "$ranges" | awk -v p="$p" '$1 <= p && p <= $2 {print $1"-"$2; exit}')
    [ -z "$hit" ] || bad "port $p" "inside a Windows excluded port range ($hit). Admin PowerShell: net stop winnat; netsh int ipv4 add excludedportrange protocol=tcp startport=$p numberofports=1; net start winnat"
  done
fi

# 3. One-time gitignored artifacts (machine-local by design, README "fresh
#    machine" step 3). These scripts are human-run — this launcher points at
#    them, it does not run them.
if [ -f infra/spire/bootstrap/agent-cacert.pem ]; then ok "SPIRE bootstrap CA"
else bad "SPIRE bootstrap CA" "run: bash infra/spire/gen-bootstrap.sh"; fi
if [ -f infra/pki/spire-intermediate.pem ] && [ -f infra/pki/ejbca-root.pem ]; then ok "EJBCA hierarchy"
else bad "EJBCA hierarchy" "run: bash infra/pki/setup-ejbca.sh"; fi
if [ -f infra/pki/ra/ra-cert-service.p12 ] && [ -f infra/pki/ra/ejbca-tls-ca.pem ]; then ok "RA credential (M12)"
else bad "RA credential (M12)" "run: bash infra/pki/setup-employee-profile.sh"; fi
# The EJBCA hierarchy files and the ejbca-data volume are one unit. Files
# without the volume means the folder was COPIED from another machine: the
# files describe a CA that does not exist here. Regenerate, never mix.
if [ -f infra/pki/ejbca-root.pem ] && ! docker volume inspect spiffe-mcp-lab_ejbca-data >/dev/null 2>&1; then
  bad "EJBCA hierarchy vs volume" "infra/pki/*.pem exist but the ejbca-data volume does not (copied from another machine?). Delete infra/pki/*.pem infra/pki/ra/ infra/spire/bootstrap/ and re-run the three one-time scripts"
fi

# 3b. Hosts entry for the browser login redirect (issuer is http://keycloak:8080).
if ping -n 1 -w 1000 keycloak >/dev/null 2>&1 || ping -c 1 -W 1 keycloak >/dev/null 2>&1; then ok "hosts entry 'keycloak'"
else say "hosts entry 'keycloak'" "MISSING — browser login will fail. Admin PowerShell: Add-Content C:\\Windows\\System32\\drivers\\etc\\hosts \"\`n127.0.0.1 keycloak\""; fi

# 3c. Images: present ones are reused, missing ones are built (10+ min, needs
#     internet). demo/export-images.sh / import-images.sh carry them on a USB.
want=$(cd infra && docker compose --profile demo --profile pki --profile tools config --images 2>/dev/null | sort -u)
have=0; total=0
for img in $want; do total=$((total+1)); docker image inspect "$img" >/dev/null 2>&1 && have=$((have+1)); done
if [ "$have" -eq "$total" ]; then ok "images present ($have/$total), no build needed"
else say "images present ($have/$total)" "the rest will be BUILT now (needs internet, ~10 min first time; or import from USB: bash demo/import-images.sh <dir>)"; fi

# 4. LLM provider (D-039). Local ollama needs nothing here (pulled by
#    reset.sh). A hosted provider needs its key and a reachable endpoint NOW,
#    not at the first chat message in front of the audience.
#    infra/.env written by Notepad (UTF-8 BOM) or by PowerShell `>` (UTF-16)
#    silently selects NOTHING: the first key becomes "\xEF\xBB\xBFLLM_PROVIDER"
#    or the whole file is NUL-riddled. Both fall back to ollama without a word.
if [ -f infra/.env ]; then
  if [ "$(LC_ALL=C tr -d '\000' < infra/.env | wc -c)" -ne "$(wc -c < infra/.env)" ]; then
    bad "infra/.env encoding" "contains NUL bytes (UTF-16, typically PowerShell '>'). Re-save as UTF-8 (Notepad: Save As → Encoding UTF-8; or: Set-Content -Encoding utf8)"
  elif [ "$(head -c 3 infra/.env | od -An -tx1 | tr -d ' \n')" = "efbbbf" ]; then
    bad "infra/.env encoding" "starts with a UTF-8 BOM (Notepad default). Re-save as 'UTF-8' not 'UTF-8 with BOM' (VS Code: bottom bar → UTF-8 → Save with encoding)"
  else ok "infra/.env is plain UTF-8"; fi
  n=$(grep -cE '^[A-Z_]+=' infra/.env 2>/dev/null || echo 0)
  ok "infra/.env read: $n variable(s) → effective LLM_PROVIDER=$LLM_PROVIDER"
else
  ok "no infra/.env → LLM_PROVIDER=$LLM_PROVIDER (create infra/.env to use a hosted model)"
fi
if [ "$LLM_PROVIDER" = ollama ]; then ok "LLM provider: ollama (local, no credential)"
elif [ -z "$LLM_API_KEY" ]; then bad "LLM provider: $LLM_PROVIDER" "LLM_API_KEY empty — put it in infra/.env (gitignored)"
elif curl -s --max-time 10 -H "Authorization: Bearer $LLM_API_KEY" "$LLM_BASE_URL/models" 2>/dev/null \
       | grep -q "\"id\": *\"$LLM_MODEL\""; then ok "LLM provider: $LLM_PROVIDER ($LLM_MODEL @ $LLM_BASE_URL)"
else bad "LLM provider: $LLM_PROVIDER" "$LLM_BASE_URL/models does not list $LLM_MODEL with this key (network? key? model pin?)"; fi

echo
if [ "$fail" -ne 0 ]; then
  echo "PREFLIGHT FAIL — fix the lines above, then re-run demo/up.sh"
  exit 1
fi
echo "PREFLIGHT PASS"
[ "${1:-}" = "--check" ] && exit 0
echo

# 4. The launch itself. Deterministic; recreates the volume-less Keycloak realm.
bash demo/reset.sh --full

# 5. Trust nothing unverified.
bash demo/checklist.sh --full

echo
echo "Console: http://localhost:8090  (alice / alice-password) — LLM provider: $LLM_PROVIDER"
