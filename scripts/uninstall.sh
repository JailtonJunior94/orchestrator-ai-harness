#!/usr/bin/env bash
# orchestrator-ai-harness / scripts / uninstall.sh
#
# Espelho do instalador. Confirmacao padrao NAO.
#
# O QUE ESTE SCRIPT NUNCA TOCA, por desenho:
#   - o repositorio do harness
#   - os `.lt/` dos projetos (specs, audit, config do squad) — sao dados de trabalho
#   - sessoes, memoria, historico
#   - os symlinks arquivados em ~/.claude/lt/legacy-symlinks/
#   - qualquer chave do settings.json que nao seja a nossa
#
# Desinstalar o harness nao pode custar o trabalho de ninguem.

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Perfil de configuracao do Claude Code. Esta maquina pode ter varios (~/.claude,
# ~/.claude-work, ~/.claude-alt), selecionados por CLAUDE_CONFIG_DIR — e instalar no
# perfil errado significa que o harness simplesmente nao aparece na sessao de quem o instalou.
LT_CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
MKT="lt"; KEEP_CACHE=0; KEEP_MKT=0; KEEP_SL=0; YES=0; DRY=0; PROJECT_DIR=""; HOSTS_GLOBAL=0

if [ -t 1 ]; then C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_OFF=$'\033[0m'
else C_OK=""; C_WARN=""; C_OFF=""; fi
ok()   { printf '  %s✓%s %s\n' "$C_OK" "$C_OFF" "$*"; }
warn() { printf '  %s!%s %s\n' "$C_WARN" "$C_OFF" "$*"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --keep-cache) KEEP_CACHE=1; shift ;;
    --keep-marketplace) KEEP_MKT=1; shift ;;
    --keep-statusline) KEEP_SL=1; shift ;;
    --yes|-y) YES=1; shift ;;
    --config-dir)
      # Perfil de configuracao alvo. Esta maquina pode ter varios (~/.claude,
      # ~/.claude-work, ~/.claude-alt) e o `claude` os seleciona por CLAUDE_CONFIG_DIR.
      # Instalar no perfil errado e' silencioso: nao da erro, o harness simplesmente nao
      # aparece na sessao.
      CLAUDE_CONFIG_DIR="$(cd "$2" 2>/dev/null && pwd || printf '%s' "$2")"
      export CLAUDE_CONFIG_DIR
      LT_CFG="$CLAUDE_CONFIG_DIR"
      shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --project) PROJECT_DIR="$2"; shift 2 ;;
    --hosts-global) HOSTS_GLOBAL=1; shift ;;
    -h|--help) printf 'uso: uninstall.sh [--project <repo-consumidor>] [--hosts-global] [--keep-cache] [--keep-marketplace] [--keep-statusline] [--config-dir <dir>] [--dry-run] [--yes]\n'; exit 0 ;;
    *) printf 'flag desconhecida: %s\n' "$1" >&2; exit 2 ;;
  esac
done

printf '\n── desinstalar o harness LT\n'
printf '  NAO serao tocados: o repo, os .lt/ dos projetos, sessoes, memoria e os symlinks arquivados.\n'
# Com varios perfis na maquina, dizer em qual se esta operando e' a unica defesa contra remover
# do perfil errado — o sintoma seria "desinstalei e continua la", sem erro nenhum.
printf '  perfil: %s\n' "$LT_CFG"

if [ "$DRY" -eq 0 ] && [ "$YES" -eq 0 ] && [ -t 0 ]; then
  printf '\n  Prosseguir? [y/N] '
  read -r a
  case "$a" in [yY]*) ;; *) printf '  cancelado.\n'; exit 0 ;; esac
fi

if [ -n "$PROJECT_DIR" ] && [ -f "$PROJECT_DIR/.lt-harness/manifest.json" ]; then
  if [ "$DRY" -eq 1 ]; then
    python3 "$REPO_ROOT/plugins/lt/scripts/reconcile-hosts.py" uninstall --project "$PROJECT_DIR" --dry-run
  else
    python3 "$REPO_ROOT/plugins/lt/scripts/reconcile-hosts.py" uninstall --project "$PROJECT_DIR" \
      || { printf 'falha ao remover adaptadores multi-host\n' >&2; exit 1; }
  fi
  ok "adaptadores multi-host processados"
fi

# Escopo global so' sai quando pedido: remover do perfil do usuario os adaptadores de Codex,
# Copilot e OpenCode sem o pedido explicito desligaria a governanca em hosts que a pessoa nem
# estava olhando.
if [ "$HOSTS_GLOBAL" -eq 1 ]; then
  if [ "$DRY" -eq 1 ]; then
    python3 "$REPO_ROOT/plugins/lt/scripts/reconcile-hosts.py" uninstall --scope global --dry-run
  else
    python3 "$REPO_ROOT/plugins/lt/scripts/reconcile-hosts.py" uninstall --scope global \
      || { printf 'falha ao remover adaptadores multi-host globais\n' >&2; exit 1; }
  fi
  ok "adaptadores multi-host globais processados"
fi

# Os tres alvos (settings + statusline, registry, cache) saem pelo inverso do reconciliador, com
# as mesmas primitivas dele: confinamento de caminho, escrita atomica com backup
# (*.bak.uninstall) e escrita SO do que mudou. Antes isto era um heredoc Python aqui dentro, que
# regravava os JSON mesmo sem mudanca e reconhecia a statusline por um caminho fixo em ~/.claude
# — errado quando o perfil vem de CLAUDE_CONFIG_DIR.
UNREC_ARGS="--marketplace $MKT --plugins lt"
[ "$KEEP_CACHE" -eq 1 ] && UNREC_ARGS="$UNREC_ARGS --keep-cache"
[ "$KEEP_SL" -eq 1 ] && UNREC_ARGS="$UNREC_ARGS --keep-statusline"
[ "$DRY" -eq 1 ] && { warn "dry-run: nada sera' alterado"; UNREC_ARGS="$UNREC_ARGS --dry-run"; }
# shellcheck disable=SC2086
UNREC_OUT="$(python3 "$REPO_ROOT/scripts/lib/unreconcile-plugins.py" $UNREC_ARGS)" \
  || { printf 'falha ao desfazer settings, registro e cache — nada alem do reportado foi alterado\n' >&2; exit 1; }
printf '%s\n' "$UNREC_OUT" | while IFS= read -r line; do printf '  %s\n' "$line"; done
[ "$DRY" -eq 1 ] || ok "registro, settings e cache processados (backups em *.bak.uninstall)"

if [ "$KEEP_MKT" -eq 0 ] && [ "$DRY" -eq 0 ] && command -v claude >/dev/null 2>&1; then
  claude plugin marketplace remove "$MKT" >/dev/null 2>&1 && ok "marketplace removido" || warn "marketplace nao removido (talvez nem estivesse registrado)"
fi

printf '\n  Preservados: ~/.claude/lt/ (audit, telemetria, pendencias; so o shim da statusline sai) e os .lt/ dos projetos.\n'
printf '  Para remover tambem esses dados, apague a mao — o script nao faz isso por voce.\n\n'
