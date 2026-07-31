#!/usr/bin/env bash
# Pre-demo checklist (DEMO-PLAN P5). Clock skew FIRST — it causes more JWT
# failures than code does (CLAUDE.md §8). Add --full to also run the terminal
# acceptance (a few minutes).
set -uo pipefail
cd "$(dirname "$0")/.."
FAIL=0
say()  { printf '%-52s %s\n' "$1" "$2"; }
ok()   { say "$1" "OK"; }
bad()  { say "$1" "FAIL${2:+ ($2)}"; FAIL=1; }

# 1. Clock skew between host and the token-minting container.
KC_TIME=$(docker exec spiffe-mcp-lab-keycloak-1 date -u +%s 2>/dev/null || echo 0)
HOST_TIME=$(date -u +%s)
SKEW=$(( KC_TIME > HOST_TIME ? KC_TIME - HOST_TIME : HOST_TIME - KC_TIME ))
if [ "$KC_TIME" = 0 ]; then bad "clock skew (keycloak container)" "container not running"
elif [ "$SKEW" -le 30 ]; then ok "clock skew host<->keycloak (${SKEW}s)"
else bad "clock skew host<->keycloak" "${SKEW}s — fix this before touching anything else"; fi

# 2. Services healthy (core + demo profile).
for svc in spire-server spire-agent keycloak mcp-server ollama agent-web; do
  state=$(docker inspect -f '{{.State.Health.Status}}' "spiffe-mcp-lab-${svc}-1" 2>/dev/null || echo missing)
  [ "$state" = healthy ] && ok "service $svc" || bad "service $svc" "$state"
done

# 3. Demo model present (never pulled mid-demo).
docker exec spiffe-mcp-lab-ollama-1 ollama list 2>/dev/null | grep -q "qwen3.5:4b" \
  && ok "demo model qwen3.5:4b present" || bad "demo model" "run infra/ollama/pull-model.sh"

# 4. Ports answering from the host.
curl -s -o /dev/null --max-time 5 http://localhost:8080/realms/lab/.well-known/openid-configuration \
  && ok "keycloak :8080" || bad "keycloak :8080"
curl -sk -o /dev/null --max-time 5 https://localhost:8443 2>/dev/null; [ $? -ne 7 ] \
  && ok "mcp-server :8443 (TLS answering)" || bad "mcp-server :8443"
curl -s -o /dev/null --max-time 5 http://localhost:8090/ \
  && ok "agent-web :8090" || bad "agent-web :8090"

# 5. Browser demo prerequisite: 'keycloak' must resolve on the HOST for the
#    login redirect (issuer is http://keycloak:8080, D-005). Warning only —
#    the scripted checks use curl --resolve instead.
if ping -n 1 keycloak >/dev/null 2>&1 || ping -c 1 keycloak >/dev/null 2>&1; then
  ok "hosts entry for 'keycloak' (browser login will work)"
else
  say "hosts entry for 'keycloak'" "MISSING — add '127.0.0.1 keycloak' to the hosts file for the live browser demo"
fi

# 6. Full terminal acceptance (optional, minutes).
if [ "${1:-}" = "--full" ]; then
  bash infra/acceptance.sh >/dev/null 2>&1 && ok "acceptance.sh (all five rejections)" || bad "acceptance.sh"
fi

echo
[ $FAIL -eq 0 ] && echo "CHECKLIST PASS — go on stage." || echo "CHECKLIST FAIL — fix before the demo."
exit $FAIL
