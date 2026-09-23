#!/usr/bin/env bash
# lt / scripts / guided-mode.sh
#
# Resolve o dial `guided`. Precedencia: LT_GUIDED > .lt/config.yaml > off.
#
# O dial NASCE `off` e atualizar o harness nunca o move. Apertar o parafuso de alguem sem que a
# pessoa tenha pedido e' o caminho mais curto para o harness ser desinstalado — especialmente
# numa organizacao que ainda nao tem cultura de gate.
#
# HOOK DE SEGURANCA NAO CONSULTA ESTE SCRIPT. Nunca. O dial regula rigor de PROCESSO.
#
# Subcomandos:
#   get                  -> off | balanced | strict
#   is-trivial <alvo>    -> exit 0 se o alvo e' isento de gate de processo

set -uo pipefail

resolve() {
  lt_raw="${LT_GUIDED:-}"
  if [ -z "$lt_raw" ]; then
    lt_cfg="${CLAUDE_PROJECT_DIR:-.}/.lt/config.yaml"
    if [ -r "$lt_cfg" ]; then
      lt_raw="$(sed -n 's/^[[:space:]]*guided:[[:space:]]*\([a-zA-Z]*\).*/\1/p' "$lt_cfg" | head -1)"
    fi
  fi
  # bash 3.2: sem ${var,,}
  lt_raw="$(printf '%s' "$lt_raw" | tr '[:upper:]' '[:lower:]')"
  case "$lt_raw" in
    off|balanced|strict) printf '%s\n' "$lt_raw" ;;
    *) printf 'off\n' ;;
  esac
}

is_trivial() {
  case "$1" in
    *.md|*.markdown|*.txt|*.rst) return 0 ;;
    */docs/*|docs/*) return 0 ;;
    */README*|README*|*/LICENSE|LICENSE|*/CHANGELOG*|CHANGELOG*) return 0 ;;
    *) return 1 ;;
  esac
}

case "${1:-get}" in
  get) resolve ;;
  is-trivial) [ $# -ge 2 ] || exit 1; is_trivial "$2" ;;
  *) printf 'uso: guided-mode.sh [get|is-trivial <alvo>]\n' >&2; exit 2 ;;
esac
