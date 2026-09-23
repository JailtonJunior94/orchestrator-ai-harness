#!/usr/bin/env bash
# lt / hooks / stop-validate-session-end.sh
# Categoria: GOVERNANCA
#
# No fim de cada resposta, AVISA sobre tarefa `in_progress`/`done` sem relatorio de execucao, ou
# `done` cujo relatorio nao aponta um execution-result existente. A varredura e'
# `lt-sdd.sh session-audit`, sobre todos os bundles do repo.
#
# POR QUE AVISO E NAO BLOQUEIO (o gate de origem devolvia decision=block): o Stop dispara a cada
# turno, inclusive no meio de uma execucao legitima — tarefa `in_progress` sem relatorio ainda e'
# o estado NORMAL de quem esta implementando. Bloquear ali prenderia a sessao em loop ate o
# `stop_hook_active` soltar. O aviso vai para a pessoa (systemMessage), que decide.
#
# No-op fora de repo que adotou o harness (sem .lt/config.yaml) e no proprio repo do harness.
# Fail-open em qualquer erro: hook de encerramento que falha nao pode impedir o encerramento.

set -uo pipefail
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

PROJECT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
[ -f "$PROJECT/plugins/lt/.claude-plugin/plugin.json" ] && exit 0
[ -f "$PROJECT/.lt/config.yaml" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0
cat >/dev/null 2>&1 || true

FINDINGS="$(cd "$PROJECT" && LT_PROJECT_DIR="$PROJECT" python3 "$PLUGIN_ROOT/lib/sdd.py" session-audit 2>/dev/null | head -10)"
[ -n "$FINDINGS" ] || exit 0

printf '[lt] aviso de encerramento — tarefa sem evidencia:\n%s\n' "$FINDINGS" >&2
MSG="$(printf '%s' "$FINDINGS" | tr '\n' ';' | sed 's/;$//; s/;/; /g; s/\\/\\\\/g; s/"/\\"/g')"
printf '{"systemMessage":"[lt] tarefa(s) sem evidencia de execucao: %s"}\n' "$MSG"
exit 0
