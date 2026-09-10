#!/usr/bin/env bash
# Single source of the LLM deployment knobs (D-039). Sourced by demo/ and
# scripts/; compose reads the same variables from the environment (and from
# infra/.env, gitignored — the ONLY place a hosted key may live on a machine).
#
#   LLM_PROVIDER  ollama (default: local, zero credentials) | openai (any
#                 OpenAI-wire endpoint; Groq for the demo). This is the value
#                 of Spring AI's own selector `spring.ai.model.chat`.
#   LLM_BASE_URL  OpenAI-wire base. The SDK appends `chat/completions`
#                 itself and defaults to `https://api.openai.com/v1`, so the
#                 `/v1` belongs here (verified: openai-java-core ClientOptions).
#   LLM_MODEL     tools-capable model at that endpoint (docs/VERSIONS.md).
#   LLM_API_KEY   the hosted key. Never in the repo; empty for ollama.
#   LLM_REASONING_FORMAT  extra request field for reasoning models (Groq:
#                 `hidden` keeps `reasoning` out of the reply; verified). Only
#                 read by the properties file, defaulted there.
#
# Nothing here is provider code: the switch is starter + properties + env.
# Precedence: process environment > infra/.env > defaults below — so
# `LLM_PROVIDER=ollama bash scripts/check-p2.sh` runs the local path even on a
# machine whose .env selects the hosted one (compose resolves the same way).
if [ -f "$(dirname "${BASH_SOURCE[0]}")/.env" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"                       # a Windows editor writes CRLF; a stray CR in
    line="${line#$'\xEF\xBB\xBF'}"             # LLM_PROVIDER matches no provider at all (D-039 §9);
    case "$line" in ''|'#'*) continue ;; esac  # Notepad adds a UTF-8 BOM before the first key
    k="${line%%=*}"; v="${line#*=}"
    k="${k#"${k%%[![:space:]]*}"}"; k="${k%"${k##*[![:space:]]}"}"
    v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
    case "$v" in \"*\") v="${v#\"}"; v="${v%\"}" ;; \'*\') v="${v#\'}"; v="${v%\'}" ;; esac
    [ -n "$k" ] && [ -z "${!k:-}" ] && export "$k=$v"
  done < "$(dirname "${BASH_SOURCE[0]}")/.env"
fi
export LLM_PROVIDER="${LLM_PROVIDER:-ollama}"
export LLM_BASE_URL="${LLM_BASE_URL:-https://api.groq.com/openai/v1}"
export LLM_MODEL="${LLM_MODEL:-openai/gpt-oss-120b}"   # verified in Groq's /models catalog 2026-09-10 (D-039 §7)
export LLM_API_KEY="${LLM_API_KEY:-}"

# `--profile llm-local` only when the local model is the provider: the ollama
# container and its 2-3 GB volume exist on a machine only if they are used.
LLM_LOCAL_PROFILE=""
[ "$LLM_PROVIDER" = ollama ] && LLM_LOCAL_PROFILE="--profile llm-local"

# `docker run` flags for the ad-hoc agent-client container (check-p2/p3):
# the same four variables agent-web receives from compose.
llm_docker_env() {
  printf -- '-e LLM_PROVIDER=%s -e LLM_BASE_URL=%s -e LLM_MODEL=%s -e LLM_API_KEY=%s' \
    "$LLM_PROVIDER" "$LLM_BASE_URL" "$LLM_MODEL" "$LLM_API_KEY"
}
