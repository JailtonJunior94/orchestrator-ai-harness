#!/usr/bin/env bash
# lt / hooks / pre-bash-block-destructive.sh
# Categoria: SEGURANCA
#
# Bloqueia comando destrutivo irreversivel. Contem e libera o que e' reversivel dentro de git.
# Hook de SEGURANCA: NAO consulta o dial `guided`.
#
# Exit 2 bloqueia. JSON com ask pede confirmacao. Exit 0 libera.

set -uo pipefail
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LT_PLUGIN_ROOT="$PLUGIN_ROOT"
. "$PLUGIN_ROOT/lib/hook-common.sh"

INPUT="$(cat 2>/dev/null || printf '{}')"
INPUT="${INPUT:0:100000}"
case "$INPUT" in *'"command"'*) ;; *) exit 0 ;; esac

if ! command -v python3 >/dev/null 2>&1; then
  # MODO DEGRADADO — sobre-bloqueia de proposito e ANUNCIA. Um guarda que desaparece junto com
  # sua dependencia e' pior que nenhum: o time acredita estar protegido.
  printf '[lt] MODO DEGRADADO — python3 ausente; a guarda de comandos destrutivos esta sobre-bloqueando.\n' >&2
  if printf '%s' "$INPUT" | grep -Eq -e 'rm[[:space:]]+-[a-zA-Z]*[rR]|mkfs|dd[[:space:]]+if=|git[[:space:]]+reset[[:space:]]+--hard|terraform[[:space:]]+destroy|drop[[:space:]]+database|history[[:space:]]+-c'; then
    lt_audit_fire "pre-bash-block-destructive" "BLOCKED" "modo degradado"
    printf '[lt] BLOQUEADO — comando potencialmente destrutivo, e o harness esta sem python3 para avaliar contencao.\n' >&2
    printf '     Instale python3 e rode `lt:lt-doctor`, ou aprove com `lt:lt-approve destructive "<motivo>"`.\n' >&2
    exit 2
  fi
  exit 0
fi

RESULT="$(printf '%s' "$INPUT" | CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" python3 "$PLUGIN_ROOT/lib/destructive_guard.py" 2>/dev/null)"
if [ -z "$RESULT" ]; then
  printf '[lt] BLOQUEADO — o verificador de comandos destrutivos nao respondeu.\n' >&2
  lt_audit_fire "pre-bash-block-destructive" "BLOCKED" "resolvedor sem resposta"
  exit 2
fi

DECISION="$(lt_json_str "$RESULT" decision)"
# O caminho feliz (`allow`) sai sem tocar em mais nada. Extrair o motivo aqui, antes do case,
# custaria um fork em TODA chamada de ferramenta para um texto usado so quando se bloqueia.
case "$DECISION" in
  allow|'') exit 0 ;;
esac
REASON="$(lt_json_str "$RESULT" reason)"

case "$DECISION" in
  block)
    lt_audit_fire "pre-bash-block-destructive" "BLOCKED" "$REASON"
    printf '[lt] BLOQUEADO — %s\n' "$REASON" >&2
    exit 2
    ;;
  needs_approval)
    # Aprovacao fresca (300s) transforma bloqueio em liberacao. E' o unico caminho.
    if lt_has_approval "destructive" 300; then
      lt_audit_fire "pre-bash-block-destructive" "ALLOWED_BY_APPROVAL" "$REASON"
      exit 0
    fi
    lt_audit_fire "pre-bash-block-destructive" "BLOCKED" "$REASON"
    printf '[lt] BLOQUEADO — %s\n' "$REASON" >&2
    exit 2
    ;;
  *)
    exit 0
    ;;
esac
