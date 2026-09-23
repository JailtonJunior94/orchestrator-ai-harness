#!/usr/bin/env bash
# Desconhecido resolve para desconhecido: sem janela confiavel, o segmento SOME.
# Numero chutado numa barra e' pior que barra sem numero — ensina a ignorar a barra.
set -uo pipefail
IN="$(cat 2>/dev/null)"
command -v python3 >/dev/null 2>&1 || exit 0
ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
R="$(printf '%s' "$IN" | python3 "$ROOT/lib/context_pct.py" 2>/dev/null)"
case "$R" in ""|lt_ctx_unknown_window*) exit 0 ;; esac
printf 'ctx %s%%' "${R%% *}"
