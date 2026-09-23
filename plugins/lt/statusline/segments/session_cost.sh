#!/usr/bin/env bash
# Custo de IA e' decisao de engenharia — so funciona se a pessoa vir o proprio numero.
set -uo pipefail
IN="$(cat 2>/dev/null)"
C="$(printf '%s' "$IN" | sed -n 's/.*"total_cost_usd"[[:space:]]*:[[:space:]]*\([0-9.]*\).*/\1/p' | head -1)"
[ -n "$C" ] && printf '$%.2f' "$C" 2>/dev/null
