#!/usr/bin/env bash
# Quantos bloqueios de seguranca dispararam hoje neste repo.
# Sem este segmento um hook bloqueante e' invisivel ate' incomodar alguem — e ai' a reacao e'
# desativar o hook, nao investigar o bloqueio.
set -uo pipefail
LOG="${LT_PROJECT:-$PWD}/.lt/audit/hook-fires.log"
[ -r "$LOG" ] || exit 0
TODAY="$(date -u +%Y-%m-%d)"
N="$(grep -c "^$TODAY.*status=BLOCKED" "$LOG" 2>/dev/null || printf 0)"
[ "${N:-0}" -gt 0 ] 2>/dev/null && printf '%s bloqueio(s)' "$N"
exit 0
