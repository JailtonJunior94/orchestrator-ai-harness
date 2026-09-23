#!/usr/bin/env bash
# orchestrator-ai-harness / scripts / update.sh
#
# Atualiza o harness instalado.
#
# ARMADILHA QUE ESTE SCRIPT EXISTE PARA EVITAR:
# `claude plugin marketplace update lt` responde "✔ Successfully updated" e NAO troca o que
# roda — ele so atualiza o clone do marketplace. Quem re-resolve o registro e' o
# `claude plugin update lt@lt --scope user`, mais o restart. Muita gente para no primeiro
# comando, ve o ✔ e conclui que atualizou.

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Perfil de configuracao do Claude Code. Esta maquina pode ter varios (~/.claude,
# ~/.claude-work, ~/.claude-alt), selecionados por CLAUDE_CONFIG_DIR — e instalar no
# perfil errado significa que o harness simplesmente nao aparece na sessao de quem o instalou.
LT_CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
MKT="lt"; PLUGINS="lt"; DRY=0; YES=0; PULL=1; HOSTS=""; PROJECT_DIR=""

if [ -t 1 ]; then C_OK=$'\033[32m'; C_BAD=$'\033[31m'; C_WARN=$'\033[33m'; C_OFF=$'\033[0m'
else C_OK=""; C_BAD=""; C_WARN=""; C_OFF=""; fi
ok()   { printf '  %s✓%s %s\n' "$C_OK" "$C_OFF" "$*"; }
warn() { printf '  %s!%s %s\n' "$C_WARN" "$C_OFF" "$*"; }
die()  { printf '  %s✗%s %s\n' "$C_BAD" "$C_OFF" "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --no-pull) PULL=0; shift ;;
    --plugins) PLUGINS="$2"; shift 2 ;;
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
    --yes|-y) YES=1; shift ;;
    --hosts) HOSTS="$2"; shift 2 ;;
    --project) PROJECT_DIR="$2"; shift 2 ;;
    -h|--help) printf 'uso: update.sh [--no-pull] [--plugins a,b] [--config-dir <dir>] [--hosts codex,copilot,opencode --project <repo>] [--dry-run] [--yes]\n'; exit 0 ;;
    *) die "flag desconhecida: $1" ;;
  esac
done

printf '\n── atualizando o harness LT\n'

if [ "$PULL" -eq 1 ]; then
  # Arvore suja + pull = conflito no meio de uma atualizacao, que e' o pior momento possivel.
  if ! git -C "$REPO_ROOT" diff --quiet 2>/dev/null || ! git -C "$REPO_ROOT" diff --cached --quiet 2>/dev/null; then
    die "arvore de trabalho suja em $REPO_ROOT — commite, guarde ou use --no-pull"
  fi
  if [ "$DRY" -eq 0 ]; then
    git -C "$REPO_ROOT" pull --ff-only 2>&1 | sed 's/^/  /' || die "git pull --ff-only falhou"
  else
    warn "dry-run: pull pulado"
  fi
  ok "repo atualizado"
else
  warn "--no-pull: usando a arvore local como esta'"
fi

OLD="$(python3 -c "import json;m=json.load(open('$REPO_ROOT/.claude-plugin/marketplace.json'));print(m['plugins'][0]['version'])" 2>/dev/null)"
ok "versao no manifesto: $OLD"

ARGS="--repo $REPO_ROOT --marketplace $MKT --plugins $PLUGINS --scope user --force-refresh"
[ "$DRY" -eq 1 ] && ARGS="$ARGS --dry-run"
# shellcheck disable=SC2086
python3 "$REPO_ROOT/scripts/lib/reconcile-plugins.py" $ARGS | sed 's/^/  /'
[ "${PIPESTATUS[0]:-0}" -eq 0 ] || die "reconciliador falhou"

if [ "$DRY" -eq 0 ]; then
  CACHE="$LT_CFG/plugins/cache/$MKT/lt/$OLD"
  [ -d "$CACHE" ] && ok "cache@$OLD presente" || die "cache@$OLD ausente apos reconciliar"
fi

if [ -n "$HOSTS" ]; then
  # Mesma regra do install.sh: sem --project o escopo e' global (perfil do usuario).
  set -- install --hosts "$HOSTS"
  if [ -n "$PROJECT_DIR" ]; then set -- "$@" --scope project --project "$PROJECT_DIR"
  else set -- "$@" --scope global; fi
  [ "$DRY" -eq 1 ] && set -- "$@" --dry-run
  python3 "$REPO_ROOT/plugins/lt/scripts/reconcile-hosts.py" "$@" || die "update multi-host falhou"
  ok "adaptadores atualizados: $HOSTS"
fi

printf '\n── proximos passos (os dois sao necessarios)\n'
printf '  1. claude plugin update lt@lt --scope user\n'
printf '     (o `marketplace update` sozinho responde ✔ mas NAO troca o que roda)\n'
printf '  2. /exit e reabrir o Claude Code\n\n'
