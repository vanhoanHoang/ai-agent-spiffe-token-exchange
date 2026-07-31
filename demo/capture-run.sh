#!/usr/bin/env bash
# Capture one complete demo run as demo/demo-run.json (DEMO_RUN schema v1) —
# the M11 console's input. Runs the P2 happy chat, the P3 scope refusal, and
# the full M9 acceptance (five rejections + chain of custody), then assembles
# the document with decoded claims and REDACTED signatures (assemble-run.py
# refuses to write if anything JWT-shaped survives).
set -euo pipefail
cd "$(dirname "$0")/.."
dkr() { MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker "$@"; }
fail() { echo "CAPTURE FAIL: $1"; exit 1; }

KC=http://localhost:8080
NET=spiffe-mcp-lab_lab
SOCK_VOL=spiffe-mcp-lab_spire-agent-socket
IMG=spiffe-mcp-lab-agent-client
TOKEN_EP=http://keycloak:8080/realms/ai-agents/protocol/openid-connect/token
PROMPT1="Use the whoami tool, then state which workload and which human you are acting for."
PROMPT2="Read the audit log and summarize the most recent entries."

bash infra/pki/issue-bundle-endpoint-cert.sh >/dev/null
(cd infra && docker compose up -d --wait spire-server spire-agent keycloak) >/dev/null || fail "core stack"
bash infra/spire/register-workloads.sh >/dev/null
bash infra/keycloak/setup-realm.sh >/dev/null
bash infra/keycloak/setup-spiffe-idp.sh >/dev/null || fail "keycloak setup"
(cd infra && docker compose --profile demo up -d --wait --wait-timeout 300) >/dev/null || fail "stack"
bash infra/ollama/pull-model.sh >/dev/null || fail "model pull"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

USER_TOKEN=$(curl -s -d grant_type=password -d client_id=test-caller -d username=alice -d password=alice-password \
  "$KC/realms/ai-agents/protocol/openid-connect/token" | sed 's/.*"access_token":"\([^"]*\)".*/\1/')
[ "${#USER_TOKEN}" -gt 100 ] || fail "no user token"
printf '%s' "$USER_TOKEN" > "$WORK/subject.jwt"

ac() { dkr run --rm --label org.lab.workload=agent-client --network "$NET" \
    -v "$SOCK_VOL":/tmp/spire-agent/public:ro \
    -e SPIFFE_ENDPOINT_SOCKET=unix:/tmp/spire-agent/public/api.sock \
    ${TOKEN+-e TOKEN="$TOKEN"} -e SUBJECT_TOKEN="$USER_TOKEN" \
    "$IMG" "$@" 2>/dev/null; }

out=$(ac token "$TOKEN_EP")
ACCESS=$(echo "$out" | grep -o '"access_token":"[^"]*"' | head -1 | cut -d'"' -f4)
[ "${#ACCESS}" -gt 100 ] || fail "exchange failed: $out"
printf '%s' "$ACCESS" > "$WORK/exchanged.jwt"

printf '%s' "$PROMPT1" > "$WORK/prompt1.txt"
T0=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
ac chat "$PROMPT1" > "$WORK/answer1.txt" || fail "happy chat failed"
(cd infra && docker compose logs --since "$T0" mcp-server 2>/dev/null) > "$WORK/logs1.txt"
grep -q "tool=whoami" "$WORK/logs1.txt" || fail "happy chat produced no whoami call"
echo "captured: happy chat"

printf '%s' "$PROMPT2" > "$WORK/prompt2.txt"
T1=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
ac chat "$PROMPT2" > "$WORK/answer2.txt" || fail "refusal chat failed"
(cd infra && docker compose logs --since "$T1" mcp-server 2>/dev/null) > "$WORK/logs2.txt"
grep -q "tool=read_audit_log DENIED" "$WORK/logs2.txt" || fail "refusal chat produced no DENIED"
echo "captured: scope refusal"

bash infra/acceptance.sh > "$WORK/acceptance.txt" 2>&1 || fail "acceptance not green during capture"
echo "captured: acceptance (5 rejections + custody)"

(cd infra && docker compose logs --tail 200 mcp-server 2>/dev/null) > "$WORK/logtail.txt"

python demo/assemble-run.py "$WORK" demo/demo-run.json
echo "CAPTURE OK"
