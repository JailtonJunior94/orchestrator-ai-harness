#!/usr/bin/env bash
# lt / hooks / post-skill-fire.sh
# Categoria: TELEMETRIA
#
# Registra disparo de skill em ~/.claude/lt/telemetry.jsonl, com rotacao gzip acima de 50 MB.
#
# POR QUE ISTO IMPORTA: e' como se mede roteamento de skill ANTES de existir eval pago. Sem esse
# dado, "a skill dispara quando deveria?" so tem resposta por impressao.
# Local only.

set -uo pipefail
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Perfil de configuracao do Claude Code. Esta maquina pode ter varios (~/.claude,
# ~/.claude-work, ~/.claude-alt), selecionados por CLAUDE_CONFIG_DIR — e instalar no
# perfil errado significa que o harness simplesmente nao aparece na sessao de quem o instalou.
LT_CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
LT_HOME="$LT_CFG/lt"
LOG="$LT_HOME/telemetry.jsonl"

INPUT="$(cat 2>/dev/null || printf '{}')"
INPUT="${INPUT:0:50000}"
command -v python3 >/dev/null 2>&1 || exit 0

mkdir -p "$LT_HOME" 2>/dev/null || exit 0

# Rotacao antes de escrever: 50 MB de JSONL num HOME e' incomodo, e ninguem percebe crescer.
if [ -f "$LOG" ]; then
  SIZE="$(stat -c %s "$LOG" 2>/dev/null || stat -f %z "$LOG" 2>/dev/null || printf 0)"
  if [ "${SIZE:-0}" -gt 52428800 ] 2>/dev/null; then
    gzip -c "$LOG" > "$LOG.$(date +%Y%m%d%H%M%S).gz" 2>/dev/null && : > "$LOG"
  fi
fi

printf '%s' "$INPUT" | python3 "$PLUGIN_ROOT/lib/telemetry_line.py" skill >> "$LOG" 2>/dev/null || true
chmod 600 "$LOG" 2>/dev/null || true

# Marcador de governanca carregada, lido por pre-write-validate-preload.sh. So as skills que
# carregam `agent-governance` contam: disparar `lt:create-prd` nao carrega regra de codigo
# nenhuma, e aceitar qualquer skill esvaziaria o gate.
SKILL="$(printf '%s' "$INPUT" | sed -n 's/.*"skill"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
SESSION="$(printf '%s' "$INPUT" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1 \
  | tr -cd 'A-Za-z0-9_-' | cut -c1-128)"
case "${SKILL#lt:}" in
  agent-governance|execute-task|execute-all-tasks|bugfix|refactor|review)
    if [ -n "$SESSION" ] && mkdir -p "$LT_HOME/preload" 2>/dev/null; then
      : > "$LT_HOME/preload/$SESSION" 2>/dev/null || true
      # Marcador e' por sessao; os de sessoes com mais de 7 dias nao servem a ninguem.
      find "$LT_HOME/preload" -type f -mtime +7 -delete 2>/dev/null || true
    fi
    ;;
esac
exit 0
