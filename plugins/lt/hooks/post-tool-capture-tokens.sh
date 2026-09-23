#!/usr/bin/env bash
# lt / hooks / post-tool-capture-tokens.sh
# Categoria: TELEMETRIA
#
# Registra, por mensagem do assistente, os tokens reais lidos do transcript em
# ~/.claude/lt/cost-daily.jsonl. O payload do PostToolUse nao traz tokens; ver lib/transcript_usage.py.
#
# NAO HA TELEMETRIA REMOTA. Os dados ficam nesta maquina. "Custo de IA e' decisao de engenharia"
# so funciona se a pessoa vir o proprio numero; mandar para um servidor muda a natureza da coisa.
#
# Escreve sempre por script do plugin, nunca por printf redigido no prompt: e' a mesma regra que
# vale para o audit trail.

set -uo pipefail
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Perfil de configuracao do Claude Code. Esta maquina pode ter varios (~/.claude,
# ~/.claude-work, ~/.claude-alt), selecionados por CLAUDE_CONFIG_DIR — e instalar no
# perfil errado significa que o harness simplesmente nao aparece na sessao de quem o instalou.
LT_CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
LT_HOME="$LT_CFG/lt"

INPUT="$(cat 2>/dev/null || printf '{}')"
INPUT="${INPUT:0:50000}"
command -v python3 >/dev/null 2>&1 || exit 0

mkdir -p "$LT_HOME" 2>/dev/null || exit 0
printf '%s' "$INPUT" | python3 "$PLUGIN_ROOT/lib/telemetry_line.py" cost "$LT_HOME/cost-cursor.txt" >> "$LT_HOME/cost-daily.jsonl" 2>/dev/null || true
chmod 600 "$LT_HOME/cost-daily.jsonl" 2>/dev/null || true
exit 0
