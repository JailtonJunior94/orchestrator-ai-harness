#!/usr/bin/env bash
# lt / hooks / pre-write-block-sensitive-paths.sh
# Categoria: SEGURANCA
#
# Bloqueia leitura e escrita em caminho sensivel (LT-FILE-001) e pede revisao humana em arquivo
# de infraestrutura (LT-FILE-002). Hook de SEGURANCA: NAO consulta o dial `guided`.

set -uo pipefail
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LT_PLUGIN_ROOT="$PLUGIN_ROOT"
. "$PLUGIN_ROOT/lib/hook-common.sh"

INPUT="$(cat 2>/dev/null || printf '{}')"
INPUT="${INPUT:0:200000}"
case "$INPUT" in *'"tool_name"'*) ;; *) exit 0 ;; esac

if ! command -v python3 >/dev/null 2>&1; then
  printf '[lt] MODO DEGRADADO — python3 ausente; guarda de caminhos sobre-bloqueando.\n' >&2
  if printf '%s' "$INPUT" | grep -Eq -e '\.ssh/|\.aws/credentials|\.gnupg|\.env"|\.pem|\.p12|\.pfx|kubeconfig|\.lt-token|approve\.log'; then
    lt_audit_fire "pre-write-block-sensitive-paths" "BLOCKED" "modo degradado"
    printf '[lt] BLOQUEADO — possivel caminho sensivel (modo degradado, sem python3).\n' >&2
    exit 2
  fi
  exit 0
fi

RESULT="$(printf '%s' "$INPUT" | CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" python3 "$PLUGIN_ROOT/lib/sensitive_paths.py" --tool write 2>/dev/null)"
[ -n "$RESULT" ] || { printf '[lt] BLOQUEADO — verificador de caminhos sem resposta.\n' >&2; exit 2; }

DECISION="$(lt_json_str "$RESULT" decision)"
# O caminho feliz (`allow`) sai sem tocar em mais nada. Extrair o motivo aqui, antes do case,
# custaria um fork em TODA chamada de ferramenta para um texto usado so quando se bloqueia.
case "$DECISION" in
  allow|'') exit 0 ;;
esac
REASON="$(lt_json_str "$RESULT" reason)"
TOKEN="$(lt_json_str "$RESULT" required_token)"

case "$DECISION" in
  block|error)
    if [ -n "$TOKEN" ] && lt_has_approval "$TOKEN" 300; then
      lt_audit_fire "pre-write-block-sensitive-paths" "ALLOWED_BY_APPROVAL" "$REASON"
      exit 0
    fi
    lt_audit_fire "pre-write-block-sensitive-paths" "BLOCKED" "$REASON"
    printf '[lt] BLOQUEADO — %s\n' "$REASON" >&2
    [ -n "$TOKEN" ] && printf '     Para liberar por 5 min: `lt:lt-approve %s "<motivo>"`\n' "$TOKEN" >&2
    exit 2
    ;;
  ask)
    lt_audit_fire "pre-write-block-sensitive-paths" "ASK" "$REASON"
    lt_emit_decision ask "$REASON"
    exit 0
    ;;
  *) exit 0 ;;
esac
