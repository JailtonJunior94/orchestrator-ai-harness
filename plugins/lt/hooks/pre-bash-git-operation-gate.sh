#!/usr/bin/env bash
# lt / hooks / pre-bash-git-operation-gate.sh
# Categoria: GOVERNANCA
#
# `commit` e `push` em branch protegida pedem confirmacao (ask); push forcado para branch
# protegida e' negado (deny). A classificacao vive em lib/git_operation_gate.py, que documenta a
# divisao de trabalho com pre-bash-block-destructive.sh: la o que APAGA trabalho, aqui o que
# PUBLICA ou REESCREVE historia compartilhada. Nenhuma regra e' duplicada entre os dois.
#
# Branches protegidas: LT_PROTECTED_BRANCHES (globs separados por espaco ou virgula), senao
# `main master trunk develop production release/* hotfix/*`.
# Escape: LT_GIT_GATE=off.
#
# FAIL-OPEN EM ERRO INTERNO, DE PROPOSITO (o gate de origem era fail-closed): o que este gate
# pega e' publicacao, que o proprio host ainda pede permissao para rodar na maioria dos modos,
# e o que e' irreversivel de verdade (`push --force`) ja esta no guarda destrutivo, que e'
# fail-closed. Travar todo `git` da sessao porque o python3 sumiu transformaria um gate de
# processo num impedimento de trabalho — e e' assim que hook vira hook desligado.

set -uo pipefail
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LT_PLUGIN_ROOT="$PLUGIN_ROOT"
. "$PLUGIN_ROOT/lib/hook-common.sh"

[ "${LT_GIT_GATE:-on}" = "off" ] && exit 0

INPUT="$(cat 2>/dev/null || printf '{}')"
INPUT="${INPUT:0:100000}"
# Caminho feliz sem fork: comando que nem menciona git nao paga o custo do python.
case "$INPUT" in *'"command"'*git*) ;; *) exit 0 ;; esac

if ! command -v python3 >/dev/null 2>&1; then
  printf '[lt] aviso — python3 ausente; o gate de operacao git nao avaliou este comando.\n' >&2
  exit 0
fi

RESULT="$(printf '%s' "$INPUT" | python3 "$PLUGIN_ROOT/lib/git_operation_gate.py" 2>/dev/null)"
DECISION="$(lt_json_str "$RESULT" decision)"
case "$DECISION" in
  ask|deny) ;;
  *) exit 0 ;;
esac
REASON="$(lt_json_str "$RESULT" reason)"
lt_audit_fire "pre-bash-git-operation-gate" "$(printf '%s' "$DECISION" | tr '[:lower:]' '[:upper:]')" "$REASON"
lt_emit_decision "$DECISION" "$REASON"
exit 0
