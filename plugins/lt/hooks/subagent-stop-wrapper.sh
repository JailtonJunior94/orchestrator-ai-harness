#!/usr/bin/env bash
# lt / hooks / subagent-stop-wrapper.sh
# Categoria: GOVERNANCA
#
# SubagentStop do `task-executor` (registrado com matcher `task-executor|lt:task-executor`; o
# nome com namespace e' como o Claude Code expoe o agente do plugin). Confere o envelope de 3
# campos que execute-all-tasks consome — status, report_path, summary — e, para `done`, o
# relatorio fisico e o checkpoint. Regra em lib/subagent_contract.py.
#
# VIOLACAO DE CONTRATO BLOQUEIA (decision=block), como no gate de origem: o motivo volta para o
# PROPRIO subagente, que ainda tem contexto para corrigir o retorno. Deixar passar significaria o
# orquestrador descobrir a violacao depois, sem ninguem com contexto para consertar.
#
# ERRO INTERNO NAO BLOQUEIA, ao contrario do gate de origem (fail-closed com
# STRICT_HOOK_FAILURES): payload sem a mensagem, python3 ausente ou crash do verificador sao
# falha do harness, nao do subagente. Bloquear ali prenderia um subagente correto por culpa da
# infraestrutura. O erro e' anunciado no stderr e o orquestrador ainda aplica a mesma cadeia de
# validacao (post-execute-task.sh).
#
# `stop_hook_active=true` libera: o bloqueio ja foi aplicado nesta retomada.
# Escape: LT_SUBAGENT_CONTRACT=warn (avisa sem bloquear) ou =off.

set -uo pipefail
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LT_PLUGIN_ROOT="$PLUGIN_ROOT"
. "$PLUGIN_ROOT/lib/hook-common.sh"

MODE="${LT_SUBAGENT_CONTRACT:-block}"
[ "$MODE" = "off" ] && exit 0

INPUT="$(cat 2>/dev/null || printf '{}')"
INPUT="${INPUT:0:500000}"

if ! command -v python3 >/dev/null 2>&1; then
  printf '[lt] aviso — python3 ausente; o contrato do task-executor nao foi conferido aqui.\n' >&2
  exit 0
fi

RESULT="$(printf '%s' "$INPUT" | python3 "$PLUGIN_ROOT/lib/subagent_contract.py" 2>/dev/null)"
DECISION="$(printf '%s\n' "$RESULT" | sed -n 1p)"
REASON="$(printf '%s\n' "$RESULT" | sed -n 2p)"

case "$DECISION" in
  ok) exit 0 ;;
  block) ;;
  skip)
    case "$REASON" in stop_hook_active|subagente\ fora*) ;; *) printf '[lt] subagent-stop: nao conferido (%s)\n' "$REASON" >&2 ;; esac
    exit 0
    ;;
  *)
    printf '[lt] subagent-stop: verificador sem resposta; contrato nao conferido aqui.\n' >&2
    exit 0
    ;;
esac

lt_audit_fire "subagent-stop-wrapper" "BLOCK" "$REASON"
if [ "$MODE" = "warn" ]; then
  printf '[lt] aviso (LT_SUBAGENT_CONTRACT=warn) — %s\n' "$REASON" >&2
  exit 0
fi
REASON_JSON="$(printf '%s' "$REASON" | tr -d '\r\n' | sed 's/\\/\\\\/g; s/"/\\"/g')"
printf '{"decision":"block","reason":"[lt] %s. Devolva EXCLUSIVAMENTE o bloco YAML com status, report_path e summary."}\n' "$REASON_JSON"
exit 0
