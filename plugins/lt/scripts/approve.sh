#!/usr/bin/env bash
# lt / scripts / approve.sh
#
# PORTA UNICA de escrita no audit trail. Toda linha de ~/.claude/lt/approve.log sai daqui.
#
# POR QUE ESTE SCRIPT EXISTE
# O caminho ingenuo seria o agente montar `printf ... >> ~/.claude/lt/approve.log` a mao. Isso
# nao funciona e nao deve funcionar: o classificador de auto mode barra redirecionamento de shell
# para dentro de ~/.claude — corretamente, porque uma trilha de auditoria que o proprio auditado
# consegue escrever com echo nao e' trilha. Sem este script, os estagios do ciclo ficam sem
# caminho de escrita nenhum.
#
# DOIS FUROS QUE O IMPROVISO DEIXAVA ABERTOS E QUE ESTE SCRIPT FECHA
#
# 1. Qualquer string entrava no campo 2, e os hooks leem por SUBSTRING
#    (`awk '$2 ~ /destructive/'`). Uma branch chamada `fix-destructive-cleanup` liberaria
#    `rm -rf` por cinco minutos. Aqui o token e' validado contra allowlist com casamento EXATO.
#
# 2. Um TAB no e-mail do operador ou no contexto deslocava as colunas e quebrava, em silencio,
#    todos os parsers. Aqui \t \r \n sao removidos de todo campo antes da escrita.
#
# FORMATO (TSV, 5 campos)
#   <epoch>\t<token>\t<contexto>\t<operador>\t<mode=human|flow|auto>
#
# O quinto campo diz COMO o checkpoint foi aprovado. Sem ele a trilha afirmaria que um humano
# conferiu quando quem conferiu foi o agente — que e' exatamente a mentira que uma trilha
# regulatoria nao pode contar.
#
# CHAMADA CANONICA (sem prefixo VAR=x; o classificador de auto mode le a forma
# `bash <plugin>/scripts/<script> <args>` de um jeito e a prefixada de outro):
#
#   bash "${CLAUDE_PLUGIN_ROOT}/scripts/approve.sh" --mode flow <token> [contexto]

set -uo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Perfil de configuracao do Claude Code. Esta maquina pode ter varios (~/.claude,
# ~/.claude-work, ~/.claude-alt), selecionados por CLAUDE_CONFIG_DIR — e instalar no
# perfil errado significa que o harness simplesmente nao aparece na sessao de quem o instalou.
LT_CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# umask antes de qualquer criacao de arquivo: o log nasce 600, nunca 644.
umask 077

LT_HOME="$LT_CFG/lt"
LOG="$LT_HOME/approve.log"
LOCKDIR="$LT_HOME/.approve.lock"

# --- Vocabulario canonico -----------------------------------------------------------------
#
# Tres classes, com posturas diferentes sob --mode auto.
#
# PHASES: os estagios do ciclo SDD. Sao processo, nao concessao de permissao: o ciclo autonomo
#   pode registrar que passou por eles.
# BYPASS: tokens que ABREM UMA GUARDA de seguranca. Sob --mode auto sao RECUSADOS — o ciclo
#   autonomo nao assina a propria licenca.
# ADHOC: registros avulsos, nenhum deles abre guarda.
PHASES="analyze-project create-prd create-technical-specification create-tasks execute-task review bugfix refactor"
BYPASS="destructive sensitive-read sensitive-write secret-write sensitive-mode-ask allowlist-change"
ADHOC="sensitive-mode-block secret-rotated exception audit-security mcp-homologation legacy-symlink-migrated"

MODE="human"
TOKEN=""
CONTEXT=""

die() { printf '[lt approve] %s\n' "$1" >&2; exit "${2:-1}"; }

usage() {
  cat >&2 <<EOF
uso: approve.sh [--mode human|flow|auto] <token> [contexto]

fases do ciclo : $PHASES
abrem guarda   : $BYPASS
avulsos        : $ADHOC

Sob --mode auto, qualquer token que abre guarda e' recusado com exit 3.
EOF
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --mode) [ $# -ge 2 ] || usage; MODE="$2"; shift 2 ;;
    --mode=*) MODE="${1#--mode=}"; shift ;;
    -h|--help) usage ;;
    --) shift; break ;;
    -*) die "flag desconhecida: $1" 2 ;;
    *) if [ -z "$TOKEN" ]; then TOKEN="$1"; else CONTEXT="$CONTEXT${CONTEXT:+ }$1"; fi; shift ;;
  esac
done

[ -n "$TOKEN" ] || usage

case "$MODE" in
  human|flow|auto) ;;
  *) die "modo invalido: '$MODE' (use human, flow ou auto)" 2 ;;
esac

# --- Classificacao do token: casamento EXATO, nunca substring ------------------------------
# `case " $LIST " in *" $TOKEN "*)` casa a palavra inteira cercada de espacos. E' isto que impede
# que `fix-destructive-cleanup` seja aceito como `destructive`.
classify() {
  case " $PHASES " in *" $1 "*) printf 'phase\n'; return 0 ;; esac
  case " $BYPASS " in *" $1 "*) printf 'bypass\n'; return 0 ;; esac
  case " $ADHOC "  in *" $1 "*) printf 'adhoc\n';  return 0 ;; esac
  printf 'unknown\n'
}

CLASS="$(classify "$TOKEN")"

if [ "$CLASS" = "unknown" ]; then
  die "token fora do vocabulario: '$TOKEN'
  fases : $PHASES
  guarda: $BYPASS
  avulso: $ADHOC" 2
fi

# O ciclo autonomo nao assina a propria licenca.
if [ "$MODE" = "auto" ] && [ "$CLASS" = "bypass" ]; then
  die "'$TOKEN' abre uma guarda de seguranca e foi RECUSADO em --mode auto.
  Um humano precisa aprovar este bypass: rode o mesmo comando com --mode human." 3
fi

# --- Sanitizacao --------------------------------------------------------------------------
# \t quebra as colunas; \r e \n quebram a linha. Removidos, nunca escapados: campo de auditoria
# nao precisa carregar caractere de controle.
sanitize() {
  printf '%s' "$1" | tr -d '\t\r\n' | sed 's/[[:cntrl:]]//g'
}

OPERATOR="$(git config user.email 2>/dev/null || true)"
[ -n "$OPERATOR" ] || OPERATOR="${USER:-desconhecido}"

TOKEN="$(sanitize "$TOKEN")"
CONTEXT="$(sanitize "$CONTEXT")"
OPERATOR="$(sanitize "$OPERATOR")"
[ -n "$CONTEXT" ] || CONTEXT="-"

# --- Escrita fail-closed -------------------------------------------------------------------
# Log que nao da' para escrever e' erro, nunca skip silencioso. Um harness que "aprova" sem
# conseguir registrar e' pior que um harness que recusa.
ensure_log_writable() {
  mkdir -p "$LT_HOME" 2>/dev/null || die "nao consegui criar $LT_HOME"
  chmod 700 "$LT_HOME" 2>/dev/null || true
  if [ ! -e "$LOG" ]; then
    : > "$LOG" 2>/dev/null || die "nao consegui criar $LOG"
  fi
  chmod 600 "$LOG" 2>/dev/null || true
  [ -w "$LOG" ] || die "sem permissao de escrita em $LOG"
}

# shellcheck source=../lib/lt-lock.sh
. "$PLUGIN_ROOT/lib/lt-lock.sh"

append_line() {
  before=$(wc -l < "$LOG" 2>/dev/null | tr -d ' ')
  printf '%s\t%s\t%s\t%s\tmode=%s\n' "$(date +%s)" "$TOKEN" "$CONTEXT" "$OPERATOR" "$MODE" >> "$LOG" \
    || die "falha ao escrever em $LOG"
  after=$(wc -l < "$LOG" 2>/dev/null | tr -d ' ')
  # Confirma que a linha entrou de fato. `>>` pode falhar por disco cheio sem que o printf
  # devolva erro visivel; sem esta checagem o script diria "registrado" sem ter registrado.
  [ "$after" -gt "$before" ] || die "a linha nao entrou em $LOG (antes=$before depois=$after)"
}

ensure_log_writable

if lt_lock "$LOCKDIR" 5; then
  append_line
  lt_unlock "$LOCKDIR"
else
  die "nao consegui o lock de $LOG em 5s"
fi

printf '[lt] registrado: %s (%s) mode=%s\n' "$TOKEN" "$CLASS" "$MODE"
