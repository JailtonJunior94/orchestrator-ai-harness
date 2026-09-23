#!/usr/bin/env bash
# lt / hooks / user-prompt-context-warning.sh
# Categoria: CONTEXTO
#
# Aviso progressivo de consumo da janela: tiers 20/40/60/80 %, um aviso por session_id x tier.
# A regra "desconhecido resolve para desconhecido" esta em lib/context_pct.py, com o porque.

set -uo pipefail
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LT_PLUGIN_ROOT="$PLUGIN_ROOT"
. "$PLUGIN_ROOT/lib/hook-common.sh"

INPUT="$(cat 2>/dev/null || printf '{}')"
INPUT="${INPUT:0:100000}"
command -v python3 >/dev/null 2>&1 || exit 0

READ="$(printf '%s' "$INPUT" | python3 "$PLUGIN_ROOT/lib/context_pct.py" 2>/dev/null)"
case "$READ" in ""|lt_ctx_unknown_window*) exit 0 ;; esac

PCT="${READ%% *}"
SESSION="${READ#* }"
case "$PCT" in ''|*[!0-9]*) exit 0 ;; esac

TIER=0
[ "$PCT" -ge 20 ] && TIER=20
[ "$PCT" -ge 40 ] && TIER=40
[ "$PCT" -ge 60 ] && TIER=60
[ "$PCT" -ge 80 ] && TIER=80
[ "$TIER" -eq 0 ] && exit 0

STATE="$LT_HOME/context-warnings.json"
KEY="$SESSION:$TIER"
[ -r "$STATE" ] && grep -qF -- "$KEY" "$STATE" 2>/dev/null && exit 0
mkdir -p "$LT_HOME" 2>/dev/null && printf '%s\n' "$KEY" >> "$STATE" 2>/dev/null || true

printf '[lt] janela de contexto em ~%s%% (tier %s%%).\n' "$PCT" "$TIER" >&2
if [ "$TIER" -ge 60 ]; then
  printf '     Considere fechar o ciclo atual ou abrir uma sessao nova para a proxima tarefa.\n' >&2
fi
exit 0
