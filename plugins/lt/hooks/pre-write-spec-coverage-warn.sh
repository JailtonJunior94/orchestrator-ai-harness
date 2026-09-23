#!/usr/bin/env bash
# lt / hooks / pre-write-spec-coverage-warn.sh
# Categoria: PROCESSO
#
# UNICO hook deste plugin que consulta o dial `guided`. Aplica o invariante I-1 (PRD-first):
# codigo que muda comportamento deveria ter spec ativa.
#
#   off      -> avisa no stderr, nao interrompe (PADRAO)
#   balanced -> permissionDecision=ask
#   strict   -> exit 2
#
# So atua em caminho de CODIGO. Prosa nunca e' gateada: bloquear a edicao de um README por falta
# de spec e' o tipo de atrito que faz o time desligar o harness inteiro.

set -uo pipefail
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LT_PLUGIN_ROOT="$PLUGIN_ROOT"
. "$PLUGIN_ROOT/lib/hook-common.sh"

INPUT="$(cat 2>/dev/null || printf '{}')"
INPUT="${INPUT:0:200000}"
case "$INPUT" in *'"tool_name"'*) ;; *) exit 0 ;; esac

GUIDED="$(bash "$PLUGIN_ROOT/scripts/guided-mode.sh" get 2>/dev/null || printf 'off')"
[ "$GUIDED" = "off" ] || [ "$GUIDED" = "balanced" ] || [ "$GUIDED" = "strict" ] || GUIDED=off

FILE="$(lt_json_str "$INPUT" file_path)"
[ -n "$FILE" ] || exit 0

# Prosa e documentacao nunca sao gateadas.
bash "$PLUGIN_ROOT/scripts/guided-mode.sh" is-trivial "$FILE" && exit 0

# So caminhos de codigo.
case "$FILE" in
  */src/*|src/*|*/lib/*|lib/*|*/app/*|app/*|*/internal/*|internal/*|*/pkg/*|pkg/*|*/cmd/*|cmd/*|*/apps/*|apps/*) ;;
  *) exit 0 ;;
esac

PROJECT="${CLAUDE_PROJECT_DIR:-.}"
SPECS="$PROJECT/.lt/specs"

# Ha' alguma spec ativa? Presenca de um prd-*/ com tasks.md basta como sinal.
if [ -d "$SPECS" ] && ls -d "$SPECS"/prd-*/ >/dev/null 2>&1; then
  exit 0
fi

# Anti-spam: um aviso por sessao x arquivo. Hook que repete a mesma mensagem a cada Edit vira
# ruido e deixa de ser lido — que e' o mesmo que nao existir.
STATE="$LT_HOME/spec-coverage-warned.json"
SESSION="$(lt_json_str "$INPUT" session_id)"
KEY="${SESSION:-nosession}:$FILE"
if [ -r "$STATE" ] && grep -qF -- "$KEY" "$STATE" 2>/dev/null; then
  exit 0
fi
mkdir -p "$LT_HOME" 2>/dev/null && printf '%s\n' "$KEY" >> "$STATE" 2>/dev/null || true

MSG="Editando codigo sem spec ativa em .lt/specs/. O invariante PRD-first pede um requisito funcional mapeado antes da implementacao. Se for correcao isolada, rename ou bump de dependencia, o escape hatch da constitution cobre e nada precisa ser feito."

case "$GUIDED" in
  strict)
    lt_audit_fire "pre-write-spec-coverage-warn" "BLOCKED" "guided=strict, sem spec"
    printf '[lt] BLOQUEADO (guided=strict) — %s\n' "$MSG" >&2
    exit 2
    ;;
  balanced)
    lt_audit_fire "pre-write-spec-coverage-warn" "ASK" "guided=balanced, sem spec"
    lt_emit_decision ask "$MSG"
    exit 0
    ;;
  *)
    printf '[lt] aviso (guided=off) — %s\n' "$MSG" >&2
    exit 0
    ;;
esac
