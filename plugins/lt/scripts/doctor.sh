#!/usr/bin/env bash
# lt / scripts / doctor.sh
#
# Diagnostico do harness. Le e reporta; nunca conserta sozinho.
#
# Um doctor que conserta em silencio esconde o problema que deveria expor — e na proxima vez o
# mesmo estado quebrado volta, sem ninguem ter entendido a causa.
#
# Secoes: --versao --instalacao --seguranca --audit --telemetry --statusline
# Sem argumento, roda todas.

set -uo pipefail
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Perfil de configuracao do Claude Code. Esta maquina pode ter varios (~/.claude,
# ~/.claude-work, ~/.claude-alt), selecionados por CLAUDE_CONFIG_DIR — e instalar no
# perfil errado significa que o harness simplesmente nao aparece na sessao de quem o instalou.
LT_CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
LT_HOME="$LT_CFG/lt"

if [ -t 1 ]; then C_OK=$'\033[32m'; C_BAD=$'\033[31m'; C_WARN=$'\033[33m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else C_OK=""; C_BAD=""; C_WARN=""; C_DIM=""; C_OFF=""; fi
ok()   { printf '  %s✓%s %s\n' "$C_OK" "$C_OFF" "$*"; }
bad()  { printf '  %s✗%s %s\n' "$C_BAD" "$C_OFF" "$*"; }
warn() { printf '  %s!%s %s\n' "$C_WARN" "$C_OFF" "$*"; }
sec()  { printf '\n%s──%s %s\n' "$C_DIM" "$C_OFF" "$*"; }

WANT="${1:-all}"
want() { [ "$WANT" = "all" ] || [ "$WANT" = "$1" ]; }

# ── versao ─────────────────────────────────────────────────────────────────────────────────
if want --versao; then
  sec "versao"
  V="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$PLUGIN_ROOT/.claude-plugin/plugin.json" 2>/dev/null | head -1)"
  ok "plugin lt ${V:-?}"
  command -v claude >/dev/null 2>&1 && ok "claude $(claude --version 2>&1 | head -1)" || warn "CLI 'claude' ausente"
  ok "bash $(bash --version | head -1 | sed 's/.*version //; s/ .*//')"
  ok "perfil: $LT_CFG"
  command -v python3 >/dev/null 2>&1 && ok "python3 $(python3 --version 2>&1 | cut -d' ' -f2)" || bad "python3 AUSENTE — hooks e gates rodam em modo degradado"
fi

# ── instalacao ─────────────────────────────────────────────────────────────────────────────
if want --instalacao; then
  sec "instalacao"
  REG="$LT_CFG/plugins/installed_plugins.json"
  SET="$LT_CFG/settings.json"
  if [ -r "$REG" ] && python3 -c "import json;d=json.load(open('$REG'));exit(0 if d.get('plugins',{}).get('lt@lt') else 1)" 2>/dev/null; then
    ok "registro: lt@lt presente"
  else bad "registro: lt@lt AUSENTE — rode 'bash scripts/install.sh'"; fi
  if [ -r "$SET" ] && python3 -c "import json;d=json.load(open('$SET'));exit(0 if d.get('enabledPlugins',{}).get('lt@lt') is True else 1)" 2>/dev/null; then
    ok "settings: lt@lt habilitado"
  else bad "settings: lt@lt NAO habilitado"; fi
  CACHE_ROOT="$LT_CFG/plugins/cache/lt/lt"
  if [ -d "$CACHE_ROOT" ]; then
    ok "cache: $(ls -1d "$CACHE_ROOT"/*/ 2>/dev/null | wc -l | tr -d ' ') versao(oes) em disco"
  else bad "cache ausente"; fi
  # Legado por symlink convivendo com o plugin = duas fontes da mesma skill.
  LEGACY=0
  for e in "$LT_CFG/skills"/*; do
    [ -L "$e" ] || continue
    t="$(python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$e" 2>/dev/null)"
    case "$t" in */tools/modelo-generico/*) LEGACY=$((LEGACY+1)) ;; esac
  done
  if [ "$LEGACY" -gt 0 ]; then
    warn "$LEGACY symlink(s) da distribuicao antiga ainda ativos — DUAS fontes da mesma skill"
    printf '      bash scripts/migrate-symlinks.sh --detect\n'
  else ok "sem symlinks legados"; fi
fi

# ── seguranca ──────────────────────────────────────────────────────────────────────────────
if want --seguranca; then
  sec "seguranca"
  N="$(ls -1 "$PLUGIN_ROOT/hooks"/*.sh 2>/dev/null | wc -l | tr -d ' ')"
  X="$(find "$PLUGIN_ROOT/hooks" -name '*.sh' -perm -u+x 2>/dev/null | wc -l | tr -d ' ')"
  [ "$N" = "$X" ] && ok "$N hooks, todos executaveis" || bad "$X de $N hooks executaveis — o git nao preserva +x; reinstale"
  for c in secret-patterns sensitive-paths; do
    [ -r "$PLUGIN_ROOT/config/$c.json" ] && ok "config/$c.json" || bad "config/$c.json AUSENTE"
  done
  # Invariante: hook de SEGURANCA nunca consulta o dial.
  V=0
  for f in pre-bash-block-destructive pre-bash-block-sensitive-paths pre-write-block-sensitive-paths pre-write-scan-secrets; do
    grep -q 'guided-mode.sh' "$PLUGIN_ROOT/hooks/$f.sh" 2>/dev/null && { bad "VIOLACAO: $f consulta o dial guided"; V=1; }
  done
  [ "$V" -eq 0 ] && ok "nenhum hook de seguranca consulta o dial guided"
  P="$LT_HOME/security-pending.jsonl"
  if [ -r "$P" ]; then
    C="$(grep -c '"status": *"pending"' "$P" 2>/dev/null || printf 0)"
    [ "${C:-0}" -gt 0 ] && warn "$C pendencia(s) de rotacao de credencial em aberto (LT-SEC-003)" || ok "sem pendencias de rotacao"
  else ok "sem pendencias de rotacao"; fi
fi

# ── audit ──────────────────────────────────────────────────────────────────────────────────
if want --audit; then
  sec "audit trail"
  LOG="$LT_HOME/approve.log"
  if [ -r "$LOG" ]; then
    ok "$(wc -l < "$LOG" | tr -d ' ') linha(s) em ~/.claude/lt/approve.log"
    MODE="$(stat -f '%Lp' "$LOG" 2>/dev/null || stat -c '%a' "$LOG" 2>/dev/null)"
    [ "$MODE" = "600" ] && ok "permissao 600" || bad "permissao $MODE (esperado 600)"
    BADN="$(awk -F'\t' 'NF!=5' "$LOG" | wc -l | tr -d ' ')"
    [ "$BADN" = "0" ] && ok "todas as linhas com 5 campos" || bad "$BADN linha(s) fora do formato"
  else ok "audit trail ainda vazio (nada foi aprovado nesta maquina)"; fi
fi

# ── telemetria ─────────────────────────────────────────────────────────────────────────────
if want --telemetry; then
  sec "telemetria"
  for f in telemetry.jsonl cost-daily.jsonl; do
    [ -r "$LT_HOME/$f" ] && ok "$f: $(wc -l < "$LT_HOME/$f" | tr -d ' ') linha(s)" || ok "$f: vazio"
  done
  # O host nao informa o tamanho da janela; sem configuracao, o aviso de contexto fica inativo.
  # Dizer isso aqui e' o que impede o hook de voltar a ser um hook morto em silencio.
  WIN="${LT_CONTEXT_WINDOW:-$(python3 -c "import sys; sys.path.insert(0, '$PLUGIN_ROOT/lib'); import context_pct; w = context_pct.window_from_config(); print(int(w) if w else '')" 2>/dev/null)}"
  if [ -n "$WIN" ]; then ok "aviso de janela de contexto ativo (janela $WIN tokens)"
  else warn "aviso de janela de contexto INATIVO: o host nao informa o tamanho da janela"
       printf '      defina "context_window": "200k" ou "1m" em ~/.claude/lt/preferences.json\n'; fi
  printf '  %sPrivacidade: os dados ficam em %s/ (local only). Nao ha telemetria remota.%s\n' "$C_DIM" "$LT_HOME" "$C_OFF"
fi

# ── statusline ─────────────────────────────────────────────────────────────────────────────
if want --statusline; then
  sec "statusline"
  SET="$LT_CFG/settings.json"
  CUR="$(python3 -c "import json;print((json.load(open('$SET')).get('statusLine') or {}).get('command',''))" 2>/dev/null)"
  case "$CUR" in
    "") warn "nenhuma statusline configurada"
        printf '      bash scripts/install.sh --statusline\n' ;;
    *"/.claude/lt/statusline-shim.sh"*) ok "statusline do harness ativa" ;;
    *)  warn "statusline de terceiro ativa — o harness NAO a sobrescreve"
        printf '\n      Para COMPOR as duas, acrescente ao seu script:\n\n'
        printf '        # --- LT harness ---\n'
        printf '        LT_SEG="$(bash "$LT_CFG/lt/statusline-shim.sh" --segments-only 2>/dev/null)"\n'
        printf '        [ -n "$LT_SEG" ] && printf " · %%s" "$LT_SEG"\n\n' ;;
  esac
fi

printf '\n'
