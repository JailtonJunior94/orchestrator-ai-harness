#!/usr/bin/env bash
# lt / hooks / user-prompt-detect-secrets.sh
# Categoria: SEGURANCA
#
# Detecta segredo colado no prompt. Aplica LT-SEC-001 e abre pendencia de rotacao (LT-SEC-003).
#
# POSTURA: SO AVISA. UserPromptSubmit nao expoe permissionDecision — nao existe confirmacao neste
# evento. E apagar a mensagem de um humano seria pior que o risco que se quer evitar.
#
# A pendencia grava prefixo mascarado (ver lib/prompt_secret_scan.py); o segredo nunca vai a disco.

set -uo pipefail
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LT_PLUGIN_ROOT="$PLUGIN_ROOT"
. "$PLUGIN_ROOT/lib/hook-common.sh"

INPUT="$(cat 2>/dev/null || printf '{}')"
INPUT="${INPUT:0:200000}"
command -v python3 >/dev/null 2>&1 || exit 0
case "$INPUT" in *'"prompt"'*) ;; *) exit 0 ;; esac

LT_UID_VALUE="$(date +%s)-$$"
PENDING="$(printf '%s' "$INPUT" | CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" LT_UID="$LT_UID_VALUE" \
  python3 "$PLUGIN_ROOT/lib/prompt_secret_scan.py" 2>/dev/null)"

[ -n "$PENDING" ] || exit 0

mkdir -p "$LT_HOME" 2>/dev/null || exit 0
printf '%s\n' "$PENDING" >> "$LT_HOME/security-pending.jsonl" 2>/dev/null || exit 0
chmod 600 "$LT_HOME/security-pending.jsonl" 2>/dev/null || true

COUNT="$(printf '%s\n' "$PENDING" | grep -c . || printf 0)"
printf '[lt] ATENCAO — possivel credencial no seu prompt (%s achado(s)).\n' "$COUNT" >&2
printf '     LT-SEC-001: agentes registram o historico de mensagens. Considere a chave COMPROMETIDA.\n' >&2
printf '     Rotacione e registre: `lt:lt-approve secret-rotated %s`\n' "$LT_UID_VALUE" >&2
exit 0
