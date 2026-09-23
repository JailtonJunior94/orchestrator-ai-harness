#!/usr/bin/env bash
# lt / hooks / pre-write-validate-preload.sh
# Categoria: GOVERNANCA
#
# Nega editar CODIGO numa sessao que ainda nao carregou a governanca (skill `agent-governance`,
# direto ou por uma skill do ciclo que a carrega). A prova de carga e' o marcador de sessao que
# post-skill-fire.sh grava em <LT_HOME>/preload/<session_id> quando uma dessas skills dispara.
#
# QUANDO ESTE GATE NAO FAZ NADA — cada item e' um falso positivo que ja seria caro:
#   - repo que nao adotou o harness: sem `.lt/config.yaml` (gerado por lt:0-setup). O `.lt/`
#     sozinho nao conta: o audit dos hooks cria `.lt/audit/` em qualquer repo git;
#   - o proprio repo do harness (tem plugins/lt/.claude-plugin/plugin.json): aqui o codigo SAO
#     as regras, e exigir a skill para editar a skill seria circular;
#   - arquivo que nao e' codigo (prosa, config, spec) e tudo sob .lt/ e .claude/;
#   - payload sem session_id: sem chave de sessao nao ha como saber o que foi carregado;
#   - subagente do plugin que ja traz agent-governance pre-carregada no frontmatter
#     (task-executor, bugfixer, refactorer): skill pre-carregada nao passa pela ferramenta Skill,
#     entao nunca gravaria o marcador.
# Escapes: LT_PRELOAD_GATE=off (desliga) e LT_PRELOAD_GATE=warn (avisa sem negar).
#
# FAIL-OPEN EM ERRO INTERNO, ao contrario do gate de origem (fail-closed): este e' um gate de
# PROCESSO. O que e' seguranca (segredo, caminho sensivel, comando destrutivo) tem hook proprio e
# fail-closed. Negar toda edicao porque o marcador nao pode ser lido derrubaria o trabalho por
# um detalhe de infraestrutura.
#
# Por que `deny` e nao `ask`: o motivo volta para o agente, e a correcao esta ao alcance dele —
# invocar a skill. `ask` jogaria no humano uma pergunta que o proprio agente resolve.

set -uo pipefail
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LT_PLUGIN_ROOT="$PLUGIN_ROOT"
. "$PLUGIN_ROOT/lib/hook-common.sh"

MODE="${LT_PRELOAD_GATE:-deny}"
[ "$MODE" = "off" ] && exit 0

PROJECT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
[ -f "$PROJECT/plugins/lt/.claude-plugin/plugin.json" ] && exit 0
[ -f "$PROJECT/.lt/config.yaml" ] || exit 0

INPUT="$(cat 2>/dev/null || printf '{}')"
INPUT="${INPUT:0:200000}"

FILE="$(lt_json_str "$INPUT" file_path)"
[ -n "$FILE" ] || exit 0
case "$FILE" in
  */.lt/*|.lt/*|*/.claude/*|.claude/*) exit 0 ;;
esac
case "$FILE" in
  *.go|*.py|*.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.mts|*.cts|*.cs|*.java|*.kt|*.kts|*.rb|*.rs|\
  *.swift|*.php|*.c|*.h|*.cc|*.cpp|*.hpp|*.scala|*.ex|*.exs|*.lua|*.sql|*.sh|*.bash|*.zsh) ;;
  *) exit 0 ;;
esac

AGENT="$(lt_json_str "$INPUT" agent_type)"
case "$AGENT" in
  *task-executor|*bugfixer|*refactorer) exit 0 ;;
esac

SESSION="$(lt_json_str "$INPUT" session_id | tr -cd 'A-Za-z0-9_-' | cut -c1-128)"
[ -n "$SESSION" ] || exit 0
[ -f "$LT_HOME/preload/$SESSION" ] && exit 0

MSG="Governanca nao carregada nesta sessao para editar codigo ($FILE). Invoque a skill lt:agent-governance, ou o fluxo que a carrega (lt:execute-task, lt:bugfix, lt:refactor), e repita a edicao. Escape consciente: LT_PRELOAD_GATE=off."

if [ "$MODE" = "warn" ]; then
  lt_audit_fire "pre-write-validate-preload" "WARN" "$FILE"
  printf '[lt] aviso (LT_PRELOAD_GATE=warn) — %s\n' "$MSG" >&2
  exit 0
fi
lt_audit_fire "pre-write-validate-preload" "DENY" "$FILE"
lt_emit_decision deny "$MSG"
exit 0
