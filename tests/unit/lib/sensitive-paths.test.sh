#!/usr/bin/env bash
# tests / unit / lib / sensitive-paths.test.sh
#
# Casos do guarda de caminhos sensiveis, lidos de tests/fixtures/sensitive-cases.json.
#
# MESMA HISTORIA DO GUARDA DESTRUTIVO, e vale registrar porque a classe reapareceu:
# o guarda casava o caminho em qualquer ponto do texto do comando, entao bloqueou a sessao que
# estava escrevendo a documentacao dele. Depois de corrigir o guarda destrutivo, este ficou —
# a correcao precisa valer para os dois, e o teste existe para que nao volte num terceiro.
#
# A DISTINCAO COBRADA: caminho LIDO versus caminho apenas MENCIONADO.
#   `cat <caminho-sensivel>`            le        -> bloqueia
#   `grep -n "<caminho>" doc.md`        e' dado   -> passa
#   `bash -c "cat <caminho>"`           executa   -> bloqueia

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
. "$REPO/tests/unit/lib/assert.sh"

export CLAUDE_PLUGIN_ROOT="$REPO/plugins/lt"
export HOME="$(mktemp -d)"
export CLAUDE_CONFIG_DIR="$HOME/.claude"
trap 'rm -rf "$HOME"' EXIT

describe "guarda de caminhos sensiveis — caminho lido vs mencionado"
assert_not_scratchpad

RESULT="$(python3 "$REPO/tests/unit/lib/run-sensitive-cases.py" 2>&1)"

printf '%s\n' "$RESULT" | while IFS= read -r line; do
  case "$line" in
    OK*)   ok "${line#OK }" ;;
    FAIL*) bad "${line#FAIL }" ;;
  esac
done

PASSES="$(printf '%s\n' "$RESULT" | grep -c '^OK' || true)"
FAILS="$(printf '%s\n' "$RESULT" | grep -c '^FAIL' || true)"
LT_T_OK=$((LT_T_OK + PASSES))
LT_T_BAD=$((LT_T_BAD + FAILS))

end_describe
