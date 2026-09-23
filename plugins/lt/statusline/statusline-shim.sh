#!/usr/bin/env bash
# lt / statusline / statusline-shim.sh
#
# Vive em CAMINHO ESTAVEL (~/.claude/lt/statusline-shim.sh), fora do cache versionado.
# Resolve a versao mais nova do cache e delega para o statusline.sh dela.
#
# POR QUE COMPARACAO SEMANTICA E NAO `ls -1dr`
# Ordenacao lexica escolhe 0.9.4 em vez de 0.10.0. A barra passa a exibir dados de uma versao
# antiga enquanto os hooks ja rodam a nova — e o sintoma ("a barra viajou no tempo") nao aponta
# para a causa.
#
# --segments-only: emite so os segmentos, sem moldura. Existe para quem ja tem statusline
# propria e quer COMPOR as duas em vez de trocar uma pela outra. Nesta frota isso e' o caso
# comum, nao a excecao.

set -uo pipefail

# Perfil de configuracao do Claude Code. Esta maquina pode ter varios (~/.claude,
# ~/.claude-work, ~/.claude-alt), selecionados por CLAUDE_CONFIG_DIR — e instalar no
# perfil errado significa que o harness simplesmente nao aparece na sessao de quem o instalou.
LT_CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

CACHE_ROOT="$LT_CFG/plugins/cache/lt/lt"
INPUT="$(cat 2>/dev/null || printf '{}')"

# shellcheck source=../lib/version-compare.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib/version-compare.sh" 2>/dev/null \
  || . "$LT_CFG/lt/version-compare.sh" 2>/dev/null \
  || { printf '[lt] version-compare.sh ausente\n' >&2; exit 0; }

BEST=""
if [ -d "$CACHE_ROOT" ]; then
  for d in "$CACHE_ROOT"/*/; do
    [ -d "$d" ] || continue
    v="$(basename "$d")"
    case "$v" in ''|*[!0-9.]*) continue ;; esac
    if [ -z "$BEST" ] || vc_gt "$v" "$BEST"; then BEST="$v"; fi
  done
fi

[ -n "$BEST" ] || exit 0
TARGET="$CACHE_ROOT/$BEST/statusline/statusline.sh"
[ -x "$TARGET" ] || [ -f "$TARGET" ] || exit 0

printf '%s' "$INPUT" | LT_VERSION="$BEST" bash "$TARGET" "$@"
