#!/usr/bin/env bash
# lt / hooks / user-prompt-block-sensitive-paths.sh
# Categoria: SEGURANCA
#
# POSTURA: SO AVISA, apesar do nome herdado da classe.
# UserPromptSubmit nao expoe permissionDecision, entao nao ha' bloqueio possivel neste evento.
# O aviso existe para que a pessoa saiba ANTES que o agente tente ler o caminho — quando o
# PreToolUse vai, esse sim, bloquear.

set -uo pipefail
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

INPUT="$(cat 2>/dev/null || printf '{}')"
INPUT="${INPUT:0:100000}"
command -v grep >/dev/null 2>&1 || exit 0

if printf '%s' "$INPUT" | grep -Eq -e '\.ssh/id_|\.aws/credentials|\.gnupg/|/\.env([^.a-zA-Z]|$)|\.pem\b|\.p12\b|\.pfx\b|kubeconfig|\.lt-token|terraform\.tfstate'; then
  printf '[lt] aviso — seu pedido menciona um caminho da classe sensivel (LT-FILE-001).\n' >&2
  printf '     O harness vai bloquear a leitura quando o agente tentar abrir o arquivo.\n' >&2
  printf '     Se o acesso for legitimo: `lt:lt-approve sensitive-read "<motivo>"` (vale 5 min).\n' >&2
fi
exit 0
