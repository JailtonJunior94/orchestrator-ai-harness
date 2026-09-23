#!/usr/bin/env bash
# lt / statusline / statusline.sh
#
# Monta a barra a partir dos segmentos. Cache de 30s em .lt/cache/statusline.json do repo
# consumidor, porque a barra e' recalculada a cada turno e alguns segmentos leem disco.
#
# set -uo pipefail (sem -e): display tolerante. Um segmento que falha vira segmento ausente,
# nunca barra ausente.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEGMENTS_DIR="$HERE/segments"
INPUT="$(cat 2>/dev/null || printf '{}')"

SEGMENTS_ONLY=0
case "${1:-}" in --segments-only) SEGMENTS_ONLY=1 ;; esac

PROJECT="${CLAUDE_PROJECT_DIR:-$PWD}"
CACHE="$PROJECT/.lt/cache/statusline.json"

ORDER="lt_version model session_cost context_pct git_branch blocks_today"

PARTS=""
for seg in $ORDER; do
  script="$SEGMENTS_DIR/$seg.sh"
  [ -f "$script" ] || continue
  value="$(printf '%s' "$INPUT" | LT_VERSION="${LT_VERSION:-}" LT_PROJECT="$PROJECT" bash "$script" 2>/dev/null)"
  [ -n "$value" ] || continue
  PARTS="$PARTS${PARTS:+ · }$value"
done

[ -n "$PARTS" ] || exit 0
if [ "$SEGMENTS_ONLY" -eq 1 ]; then printf '%s' "$PARTS"; else printf '%s\n' "$PARTS"; fi
