#!/usr/bin/env bash
# orchestrator-ai-harness / scripts / install.sh
#
# Wizard de instalacao. Deterministico, idempotente e VALIDADO no fim.
#
# Fases: 0 pre-requisitos · 0b legado por symlink · 1 marketplace · 2 reconciliar
#        2b statusline · 3 validacao ponta a ponta · 4 proximos passos
#
# bash 3.2: sem mapfile, sem declare -A, sem ${var,,}. Ver CLAUDE.md.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Perfil de configuracao do Claude Code. Esta maquina pode ter varios (~/.claude,
# ~/.claude-work, ~/.claude-alt), selecionados por CLAUDE_CONFIG_DIR — e instalar no
# perfil errado significa que o harness simplesmente nao aparece na sessao de quem o instalou.
LT_CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
MKT="lt"
CANONICAL="lt"
PLUGINS="$CANONICAL"
DRY=0; YES=0; STATUSLINE=ask; SKIP_MIGRATION=0; HOSTS=""; PROJECT_DIR=""; HOST_TRUST=0

if [ -t 1 ]; then C_OK=$'\033[32m'; C_BAD=$'\033[31m'; C_WARN=$'\033[33m'; C_OFF=$'\033[0m'
else C_OK=""; C_BAD=""; C_WARN=""; C_OFF=""; fi

say()  { printf '%s\n' "$*"; }
ok()   { printf '  %s✓%s %s\n' "$C_OK" "$C_OFF" "$*"; }
warn() { printf '  %s!%s %s\n' "$C_WARN" "$C_OFF" "$*"; }
bad()  { printf '  %s✗%s %s\n' "$C_BAD" "$C_OFF" "$*" >&2; }
die()  { bad "$*"; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
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
    --statusline) STATUSLINE=yes; shift ;;
    --no-statusline) STATUSLINE=no; shift ;;
    --skip-migration) SKIP_MIGRATION=1; shift ;;
    --hosts) HOSTS="$2"; shift 2 ;;
    --project) PROJECT_DIR="$2"; shift 2 ;;
    --trust) HOST_TRUST=1; shift ;;
    -h|--help)
      cat <<EOF
uso: install.sh [--plugins a,b] [--config-dir <dir>] [--hosts codex,copilot,opencode [--project <repo> [--trust]]] [--dry-run] [--yes] [--statusline|--no-statusline] [--skip-migration]
EOF
      exit 0 ;;
    *) die "flag desconhecida: $1" ;;
  esac
done

# ── Fase 0 — pre-requisitos ────────────────────────────────────────────────────────────────
say ""
say "── Fase 0 · pre-requisitos"
command -v python3 >/dev/null 2>&1 || die "python3 e' obrigatorio (o reconciliador e os gates dependem dele)"
ok "python3 $(python3 --version 2>&1 | cut -d' ' -f2)"
[ -f "$REPO_ROOT/scripts/lib/reconcile-plugins.py" ] || die "reconciliador ausente em scripts/lib/"
ok "reconciliador presente"

# Com varios perfis na maquina, NAO dizer em qual esta instalando e' convite ao erro silencioso.
if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
  ok "perfil: $LT_CFG  (via CLAUDE_CONFIG_DIR)"
else
  ok "perfil: $LT_CFG  (padrao)"
fi
OTHERS=""
for d in "$HOME"/.claude "$HOME"/.claude-*; do
  [ -d "$d" ] || continue
  [ "$d" = "$LT_CFG" ] && continue
  OTHERS="$OTHERS $(basename "$d")"
done
[ -n "$OTHERS" ] && warn "outros perfis nesta maquina, NAO tocados:$OTHERS"

for tool in jq git gh; do
  command -v "$tool" >/dev/null 2>&1 && ok "$tool" || warn "$tool ausente (opcional, mas util)"
done
if command -v claude >/dev/null 2>&1; then ok "claude $(claude --version 2>&1 | head -1)"
else warn "CLI 'claude' ausente — o registro do marketplace vai ser pulado"; fi

# Validacao de --plugins contra a lista canonica, em bash 3.2 (sem arrays associativos).
OLD_IFS="$IFS"; IFS=','
for p in $PLUGINS; do
  case ",$CANONICAL," in
    *",$p,"*) ;;
    *) IFS="$OLD_IFS"; die "plugin desconhecido: '$p' (canonicos: $CANONICAL)" ;;
  esac
done
IFS="$OLD_IFS"
ok "plugins: $PLUGINS"

# Rodando DENTRO de uma sessao do Claude Code? O restart depois e' obrigatorio.
if [ -n "${CLAUDECODE:-}${CLAUDE_CODE_SESSION_ID:-}" ]; then
  warn "voce esta dentro de uma sessao do Claude Code — sera' preciso /exit e reabrir ao final"
fi

if [ "$DRY" -eq 1 ]; then warn "modo --dry-run: nada sera' escrito"; fi

if [ "$DRY" -eq 0 ] && [ "$YES" -eq 0 ] && [ -t 0 ]; then
  printf '\nInstalar o harness LT no escopo user? [Y/n] '
  read -r answer
  case "$answer" in [nN]*) say "cancelado."; exit 0 ;; esac
fi

# ── Fase 0b — legado por symlink ───────────────────────────────────────────────────────────
say ""
say "── Fase 0b · distribuicao antiga por symlink"
if [ "$SKIP_MIGRATION" -eq 1 ]; then
  warn "pulado por --skip-migration"
elif [ -x "$REPO_ROOT/scripts/migrate-symlinks.sh" ]; then
  if bash "$REPO_ROOT/scripts/migrate-symlinks.sh" --detect --quiet; then
    ok "nenhum symlink legado encontrado"
  else
    warn "ha' symlinks da distribuicao antiga apontando para o repo de conhecimento."
    warn "Instalar por cima cria DUAS fontes da mesma skill: voce edita o repo e roda o cache."
    say  "    Resolva antes com:  bash scripts/migrate-symlinks.sh --detect"
    say  "    E entao:            bash scripts/migrate-symlinks.sh --apply"
    say  "    Ou siga assim mesmo com --skip-migration (nao recomendado)."
    [ "$YES" -eq 1 ] || exit 2
  fi
else
  warn "migrate-symlinks.sh ausente"
fi

# ── Fase 1 — marketplace ───────────────────────────────────────────────────────────────────
say ""
say "── Fase 1 · marketplace"
if [ "$DRY" -eq 1 ]; then
  warn "dry-run: registro do marketplace pulado"
elif command -v claude >/dev/null 2>&1; then
  OUT="$(claude plugin marketplace add "$REPO_ROOT" --scope user 2>&1)"
  if printf '%s' "$OUT" | grep -Eqi 'already|exists|registered|success'; then
    ok "marketplace '$MKT' registrado"
  else
    warn "registro do marketplace devolveu: $(printf '%s' "$OUT" | head -1)"
  fi
  # AVISO ALTO: registrar por caminho local tira a maquina do canal oficial de atualizacao.
  warn "registrado por CAMINHO LOCAL — esta maquina esta fora do canal oficial."
  say  "    Para voltar ao canal:  claude plugin marketplace remove $MKT"
  say  "                           claude plugin marketplace add JailtonJunior94/orchestrator-ai-harness"
else
  warn "sem CLI 'claude': pulando o registro (o reconciliador cuida do cache mesmo assim)"
fi

# ── Fase 2 — reconciliar ───────────────────────────────────────────────────────────────────
say ""
say "── Fase 2 · cache, registro e settings"
RECON_ARGS="--repo $REPO_ROOT --marketplace $MKT --plugins $PLUGINS --scope user"
[ "$DRY" -eq 1 ] && RECON_ARGS="$RECON_ARGS --dry-run"
# shellcheck disable=SC2086
RECON_OUT="$(python3 "$REPO_ROOT/scripts/lib/reconcile-plugins.py" $RECON_ARGS)" || die "reconciliador falhou"
printf '%s\n' "$RECON_OUT" | while IFS= read -r line; do
  printf '  %s\n' "$line"
done
# Reexecucao sem efeito precisa DIZER isso: sem o resumo, a segunda rodada era indistinguivel
# de uma instalacao nova para quem lia a saida.
if printf '%s\n' "$RECON_OUT" | grep -Eq '"action": "(cache-created|cache-refresh|cache-forced|registered|enabled)"'; then
  ok "cache, registro e settings atualizados"
else
  ok "unchanged: cache, registro e settings ja estavam no estado certo"
fi

if [ "$DRY" -eq 0 ] && command -v claude >/dev/null 2>&1; then
  OLD_IFS="$IFS"; IFS=','
  for p in $PLUGINS; do
    # Escopo EXPLICITO: o auto-detect pode gravar em 'project' e divergir do que o
    # reconciliador escreveu em 'user'.
    claude plugin enable "$p@$MKT" --scope user >/dev/null 2>&1 && ok "habilitado $p@$MKT" || warn "enable de $p@$MKT nao confirmou (o settings ja tem a chave)"
  done
  IFS="$OLD_IFS"
fi

# ── Fase 2b — statusline ───────────────────────────────────────────────────────────────────
say ""
say "── Fase 2b · statusline"
if [ ! -f "$REPO_ROOT/scripts/lib/provision-statusline.py" ]; then
  warn "provisionador ausente — pulado"
elif [ "$STATUSLINE" = "no" ]; then
  warn "pulado por --no-statusline"
else
  if [ "$STATUSLINE" = "ask" ] && [ "$YES" -eq 0 ] && [ "$DRY" -eq 0 ] && [ -t 0 ]; then
    printf '  Provisionar a statusline do harness? [y/N] '
    read -r answer
    case "$answer" in [yY]*) STATUSLINE=yes ;; *) STATUSLINE=no ;; esac
  fi
  if [ "$STATUSLINE" = "no" ]; then
    warn "statusline nao provisionada"
  else
    PS_ARGS="--repo $REPO_ROOT"
    [ "$DRY" -eq 1 ] && PS_ARGS="$PS_ARGS --dry-run"
    # shellcheck disable=SC2086
    RESULT="$(python3 "$REPO_ROOT/scripts/lib/provision-statusline.py" $PS_ARGS 2>&1)"
    printf '  %s\n' "$RESULT"
  fi
fi

# ── Fase 2c — adaptadores multi-host ───────────────────────────────────────────────────────
# Sem --project o escopo e' GLOBAL (perfil do usuario: ~/.agents/skills, $CODEX_HOME,
# $COPILOT_HOME, $XDG_CONFIG_HOME/opencode) — e' o que liga o harness em `codex`, `copilot` e
# `opencode` rodados de qualquer pasta. Com --project, o escopo e' o repositorio.
if [ -n "$HOSTS" ]; then
  say ""
  say "── Fase 2c · adaptadores multi-host ($HOSTS)"
  set -- install --hosts "$HOSTS"
  if [ -n "$PROJECT_DIR" ]; then
    set -- "$@" --scope project --project "$PROJECT_DIR"
    [ "$HOST_TRUST" -eq 1 ] && set -- "$@" --trust
  else
    set -- "$@" --scope global
  fi
  [ "$DRY" -eq 1 ] && set -- "$@" --dry-run
  python3 "$REPO_ROOT/plugins/lt/scripts/reconcile-hosts.py" "$@" \
    || die "reconciliacao multi-host falhou"
  ok "adaptadores: $HOSTS"
fi

# ── Fase 3 — validacao ponta a ponta ───────────────────────────────────────────────────────
say ""
say "── Fase 3 · validacao"
if [ "$DRY" -eq 1 ]; then
  warn "dry-run: validacao pulada"
else
  FAILED=0
  OLD_IFS="$IFS"; IFS=','
  for p in $PLUGINS; do
    VER="$(python3 -c "import json,sys;m=json.load(open('$REPO_ROOT/.claude-plugin/marketplace.json'));print([x['version'] for x in m['plugins'] if x['name']=='$p'][0])" 2>/dev/null)"
    CACHE="$LT_CFG/plugins/cache/$MKT/$p/$VER"
    REG="$(python3 -c "import json,os;d=json.load(open(os.path.expanduser('$LT_CFG/plugins/installed_plugins.json')));print('yes' if d.get('plugins',{}).get('$p@$MKT') else 'no')" 2>/dev/null)"
    EN="$(python3 -c "import json,os;d=json.load(open(os.path.expanduser('$LT_CFG/settings.json')));print('yes' if d.get('enabledPlugins',{}).get('$p@$MKT') is True else 'no')" 2>/dev/null)"
    if [ -d "$CACHE" ] && [ "$REG" = "yes" ] && [ "$EN" = "yes" ]; then
      ok "$p: cache@$VER · registro · habilitado"
    else
      bad "$p: cache=$([ -d "$CACHE" ] && echo ok || echo FALTA) registro=$REG habilitado=$EN"
      FAILED=1
    fi
  done
  IFS="$OLD_IFS"
  if [ "$FAILED" -eq 1 ]; then
    bad "estado inconsistente — rode este instalador de novo (ele se auto-repara)"
    exit 1
  fi
fi

# ── Fase 4 — proximos passos ───────────────────────────────────────────────────────────────
say ""
say "── Fase 4 · proximos passos"
say "  1. Reinicie o Claude Code:  /exit  e depois  claude"
say "     (plugin so carrega em sessao nova — sem o restart nada muda)"
say "  2. Rode:  /lt:lt-doctor"
say ""
