#!/usr/bin/env bash
# orchestrator-ai-harness / scripts / migrate-symlinks.sh
#
# Aposenta a distribuicao antiga por symlink (~/.claude/{skills,agents,commands} apontando para
# tools/modelo-generico/ do repo de conhecimento).
#
# ESTA PECA NAO EXISTE NO HARNESS DE REFERENCIA, porque la' nao havia nada para substituir.
# Aqui ha' um mecanismo VIVO, e instalar o plugin por cima dele cria DUAS fontes da mesma skill:
# a pessoa edita o repo e executa o cache, ou vice-versa, sem nenhum erro aparecer.
#
# GARANTIA CENTRAL: NADA E' APAGADO.
# `mv` de um symlink move o LINK, nao o alvo. O conteudo continua no repo git, intacto. O link
# vai para ~/.claude/lt/legacy-symlinks/<timestamp>/ com um manifesto que permite desfazer.
#
# CLASSIFICACAO E' PELO ALVO RESOLVIDO, NUNCA PELO NOME.
# Uma skill pessoal com nome coincidente apontando para outro lugar NAO e' nossa e nao
# pode ser tocada. Por isso cada entrada e' resolvida com realpath antes de qualquer decisao.

set -uo pipefail

# Perfil de configuracao do Claude Code. Esta maquina pode ter varios (~/.claude,
# ~/.claude-work, ~/.claude-alt), selecionados por CLAUDE_CONFIG_DIR — e instalar no
# perfil errado significa que o harness simplesmente nao aparece na sessao de quem o instalou.
LT_CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

MODE=detect
QUIET=0
RESTORE_DIR=""

if [ -t 1 ]; then C_OK=$'\033[32m'; C_BAD=$'\033[31m'; C_WARN=$'\033[33m'; C_OFF=$'\033[0m'
else C_OK=""; C_BAD=""; C_WARN=""; C_OFF=""; fi

while [ $# -gt 0 ]; do
  case "$1" in
    --detect) MODE=detect; shift ;;
    --apply) MODE=apply; shift ;;
    --restore) MODE=restore; RESTORE_DIR="${2:-}"; shift 2 ;;
    --quiet) QUIET=1; shift ;;
    -h|--help)
      cat <<EOF
uso: migrate-symlinks.sh [--detect|--apply|--restore <dir>] [--quiet]

  --detect   (padrao) so imprime o que encontrou. Exit 0 = nada a migrar; 1 = ha legado.
  --apply    arquiva os symlinks nossos e deixa o caminho livre para o plugin.
  --restore  desfaz, a partir de um diretorio de arquivo.
EOF
      exit 0 ;;
    *) printf 'flag desconhecida: %s\n' "$1" >&2; exit 2 ;;
  esac
done

say()  { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }
ok()   { [ "$QUIET" -eq 1 ] || printf '  %s✓%s %s\n' "$C_OK" "$C_OFF" "$*"; }
warn() { [ "$QUIET" -eq 1 ] || printf '  %s!%s %s\n' "$C_WARN" "$C_OFF" "$*"; }

ARCHIVE_ROOT="$LT_CFG/lt/legacy-symlinks"

# --- restore --------------------------------------------------------------------------------
if [ "$MODE" = "restore" ]; then
  [ -n "$RESTORE_DIR" ] || { printf 'informe o diretorio de arquivo\n' >&2; exit 2; }
  MANIFEST="$RESTORE_DIR/manifest.jsonl"
  [ -r "$MANIFEST" ] || { printf 'manifesto nao encontrado: %s\n' "$MANIFEST" >&2; exit 1; }
  N=0
  while IFS= read -r line; do
    FROM="$(printf '%s' "$line" | sed -n 's/.*"from"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
    BASE="$(basename "$FROM")"
    SAVED="$RESTORE_DIR/$BASE.link"
    if [ -L "$SAVED" ] && [ ! -e "$FROM" ]; then
      mv "$SAVED" "$FROM" && N=$((N+1)) && ok "restaurado: $FROM"
    else
      warn "pulado (destino ja existe ou link ausente): $FROM"
    fi
  done < "$MANIFEST"
  say "restaurados: $N"
  exit 0
fi

# --- classificacao --------------------------------------------------------------------------
classify() {  # $1 = caminho de uma entrada em ~/.claude/{skills,agents,commands}
  if [ ! -L "$1" ]; then
    if [ -d "$1" ]; then printf 'foreign-dir\n'; else printf 'other\n'; fi
    return
  fi
  tgt="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1" 2>/dev/null)"
  case "$tgt" in
    */tools/modelo-generico/skills/*|*/tools/modelo-generico/subagents/*|*/tools/modelo-generico/commands/*|*/tools/modelo-generico)
        printf 'legacy-ours\n' ;;
    *)  if [ -e "$tgt" ]; then printf 'foreign-link\n'; else printf 'dangling\n'; fi ;;
  esac
}

FOUND_OURS=0
OURS_LIST=""
say ""
say "── varredura de ~/.claude/{skills,agents,commands} e ~/.agents/skills"

for base in "$LT_CFG/skills" "$LT_CFG/agents" "$LT_CFG/commands" "$HOME/.agents/skills"; do
  [ -e "$base" ] || continue

  # Caso agressivo: o diretorio INTEIRO e' um symlink para dentro do repo de conhecimento.
  if [ -L "$base" ]; then
    k="$(classify "$base")"
    if [ "$k" = "legacy-ours" ]; then
      FOUND_OURS=$((FOUND_OURS+1)); OURS_LIST="$OURS_LIST $base"
      warn "$base -> diretorio inteiro e' symlink NOSSO"
    else
      ok "$base -> symlink de terceiro, intocado"
    fi
    continue
  fi

  [ -d "$base" ] || continue
  for entry in "$base"/*; do
    [ -e "$entry" ] || [ -L "$entry" ] || continue
    k="$(classify "$entry")"
    name="$(basename "$entry")"
    case "$k" in
      legacy-ours)
        FOUND_OURS=$((FOUND_OURS+1)); OURS_LIST="$OURS_LIST $entry"
        warn "$name -> NOSSO (aponta para o repo de conhecimento)" ;;
      foreign-link) ok "$name -> link de terceiro, intocado" ;;
      foreign-dir)  ok "$name -> diretorio real de terceiro, intocado" ;;
      dangling)     warn "$name -> link quebrado" ;;
    esac
  done
done

say ""
if [ "$FOUND_OURS" -eq 0 ]; then
  say "Nada da distribuicao antiga encontrado."
  exit 0
fi

say "Encontrados $FOUND_OURS item(ns) da distribuicao antiga."

if [ "$MODE" = "detect" ]; then
  say ""
  say "  Para aposentar (nada e' apagado — o link e' movido, o conteudo fica no repo git):"
  say "      bash scripts/migrate-symlinks.sh --apply"
  exit 1
fi

# --- apply ----------------------------------------------------------------------------------
# Recusa rodar antes do substituto existir: tirar o symlink sem o plugin instalado deixa a
# pessoa sem skill nenhuma.
REG="$LT_CFG/plugins/installed_plugins.json"
INSTALLED=no
if [ -r "$REG" ]; then
  INSTALLED="$(python3 -c "import json,sys;d=json.load(open('$REG'));print('yes' if d.get('plugins',{}).get('lt@lt') else 'no')" 2>/dev/null || printf no)"
fi
if [ "$INSTALLED" != "yes" ]; then
  printf '%s✗%s RECUSADO: o plugin lt@lt ainda nao esta instalado.\n' "$C_BAD" "$C_OFF" >&2
  printf '   Aposentar o symlink agora deixaria voce sem skill nenhuma.\n' >&2
  printf '   Rode primeiro: bash scripts/install.sh --skip-migration\n' >&2
  exit 3
fi

TS="$(date -u +%Y%m%dT%H%M%SZ)"
ARCHIVE="$ARCHIVE_ROOT/$TS"
mkdir -p "$ARCHIVE" || { printf 'nao consegui criar %s\n' "$ARCHIVE" >&2; exit 1; }
MANIFEST="$ARCHIVE/manifest.jsonl"
: > "$MANIFEST"

MOVED=0
for entry in $OURS_LIST; do
  [ -L "$entry" ] || { warn "pulado (nao e' symlink): $entry"; continue; }
  tgt="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$entry" 2>/dev/null)"
  # Manifesto ANTES do move: se algo falhar no meio, ainda da' para desfazer.
  printf '{"from":"%s","target":"%s","kind":"legacy-ours","archived_at":"%s"}\n' \
    "$entry" "$tgt" "$TS" >> "$MANIFEST"
  if mv "$entry" "$ARCHIVE/$(basename "$entry").link"; then
    MOVED=$((MOVED+1)); ok "arquivado: $(basename "$entry")"
  else
    warn "falhou ao mover: $entry"
  fi
done

# Se ~/.claude/skills era um link inteiro, recria como diretorio real para que skills pessoais
# futuras continuem funcionando.
for base in "$LT_CFG/skills" "$LT_CFG/agents" "$LT_CFG/commands"; do
  [ -e "$base" ] || mkdir -p "$base" 2>/dev/null || true
done

say ""
say "Arquivados $MOVED item(ns) em:"
say "    $ARCHIVE"
say ""
say "  NADA foi apagado: 'mv' de um symlink move o LINK, nao o alvo."
say "  O conteudo continua no repo de conhecimento, versionado."
say ""
say "  Para desfazer:"
say "      bash scripts/migrate-symlinks.sh --restore \"$ARCHIVE\""

# Trilha de auditoria, por maquina.
PLUGIN_VER="$(python3 -c "import json;m=json.load(open('$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.claude-plugin/marketplace.json'));print(m['plugins'][0]['version'])" 2>/dev/null || printf '?')"
CACHE_PLUGIN="$LT_CFG/plugins/cache/lt/lt/$PLUGIN_VER"
if [ -x "$CACHE_PLUGIN/scripts/approve.sh" ]; then
  CLAUDE_PLUGIN_ROOT="$CACHE_PLUGIN" bash "$CACHE_PLUGIN/scripts/approve.sh" \
    --mode human legacy-symlink-migrated "$(hostname 2>/dev/null || printf 'host')" >/dev/null 2>&1 || true
fi
exit 0
