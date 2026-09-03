#!/usr/bin/env bash
# Único punto de entrada aprobado para Pi en Cloud Agents (Fase 1).
# Fase 1: solo --check. No envía prompts, no autentica y no llama a un modelo.
#
# Revisiones futuras (aún no habilitadas) usarán únicamente:
#   pi --no-session --tools read,grep,find,ls
# Nunca se exponen bash, write ni edit.
set -euo pipefail

PI_PACKAGE="@earendil-works/pi-coding-agent"
PI_EXPECTED_VERSION="0.84.4"
PI_READONLY_TOOLS="read,grep,find,ls"
PI_FORBIDDEN_TOOLS="bash,write,edit"

pi_review_fail() {
  echo "!! $*" >&2
  exit 1
}

pi_review_version_token() {
  local output="$1"
  local token
  # shellcheck disable=SC2086
  for token in $output; do
    case "$token" in
      v[0-9]*.[0-9]*)
        printf '%s' "${token#v}"
        return 0
        ;;
      [0-9]*.[0-9]*)
        printf '%s' "$token"
        return 0
        ;;
    esac
  done
  return 1
}

usage() {
  cat <<'EOF'
Uso:
  .cursor/pi-review.sh --check

Fase 1 solo valida la instalación read-only. No envía prompts ni requiere
autenticación. El modo de revisión con modelo no está habilitado.
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

if [ "$#" -ne 1 ] || [ "$1" != "--check" ]; then
  usage >&2
  echo "!! Fase 1: solo está aprobado --check. No se invocará Pi con un prompt." >&2
  exit 2
fi

hash -r
pi_path="$(command -v pi || true)"
if [ -z "$pi_path" ]; then
  pi_review_fail "pi no está en PATH"
fi
if [ "$pi_path" = "/exec-daemon/pi" ]; then
  pi_review_fail "pi resolvió a /exec-daemon/pi; use el binario fijado del Cloud Build"
fi
if [ ! -x "$pi_path" ]; then
  pi_review_fail "pi en ${pi_path} no es ejecutable"
fi

# Aislar HOME: `pi --version` escribiría ~/.pi/agent/auth.json en el home real.
check_home="$(mktemp -d)"
# shellcheck disable=SC2064
trap 'rm -rf "$check_home"' EXIT
pi_output="$(HOME="$check_home" "$pi_path" --version 2>&1 || true)"
pi_reported="$(pi_review_version_token "$pi_output")" || pi_review_fail "pi --version no reportó una versión (${pi_output})"
if [ "$pi_reported" != "$PI_EXPECTED_VERSION" ]; then
  pi_review_fail "pi reportó ${pi_reported}; se esperaba ${PI_EXPECTED_VERSION}"
fi
if [ -e "${check_home}/.pi/agent/auth.json" ]; then
  echo "  note: isolated probe wrote a throwaway auth.json under mktemp (not ~/.pi)"
fi

case ",${PI_READONLY_TOOLS}," in
  *,bash,*|*,write,*|*,edit,*)
    pi_review_fail "la allowlist read-only incluye una herramienta prohibida: ${PI_READONLY_TOOLS}"
    ;;
esac
for forbidden in bash write edit; do
  case ",${PI_FORBIDDEN_TOOLS}," in
    *,${forbidden},*) ;;
    *) pi_review_fail "PI_FORBIDDEN_TOOLS no declara ${forbidden}" ;;
  esac
  case ",${PI_READONLY_TOOLS}," in
    *,${forbidden},*)
      pi_review_fail "${forbidden} no puede formar parte de PI_READONLY_TOOLS"
      ;;
  esac
done

echo "pi-review check: ok"
echo "  package:     ${PI_PACKAGE}@${PI_EXPECTED_VERSION}"
echo "  binary:      ${pi_path}"
echo "  version:     ${pi_reported}"
echo "  tools:       ${PI_READONLY_TOOLS}"
echo "  forbidden:   ${PI_FORBIDDEN_TOOLS}"
echo "  session:     --no-session (futuro; no se invocó Pi con prompt)"
echo "  auth:        none required for --check"
echo "  prompt:      not sent"
echo "  provider:    not selected in Phase 1"
echo "  model:       not selected in Phase 1"
echo "  llm_call:    no"
