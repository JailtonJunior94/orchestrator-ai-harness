#!/usr/bin/env bash
# tests / unit / lib / destructive-guard.test.sh
#
# Casos do guarda destrutivo, lidos de tests/fixtures/destructive-cases.json.
#
# POR QUE OS CASOS VIVEM NUM ARQUIVO E NAO NESTE SCRIPT
# O proprio harness bloqueia qualquer comando de shell que contenha os literais destrutivos —
# inclusive um teste que so os passa como dado. Isso foi descoberto do jeito mais direto
# possivel: o hook bloqueou a sessao que estava escrevendo este teste. Os casos ficam em JSON,
# lidos por python, que nao passa pelo PreToolUse/Bash.
#
# A DISTINCAO QUE ESTE TESTE COBRA: comando EXECUTADO versus texto que apenas CONTEM o comando.
#   `bash -c "rm -rf /"`   executa      -> tem de bloquear
#   `echo 'rm -rf /' > f`  e' dado      -> tem de passar
# Sub-detectar aqui e' vazamento; sobre-detectar faz a pessoa desligar o hook na primeira semana,
# e junto vai a protecao real.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
. "$REPO/tests/unit/lib/assert.sh"

export CLAUDE_PLUGIN_ROOT="$REPO/plugins/lt"
export HOME="$(mktemp -d)"
export CLAUDE_CONFIG_DIR="$HOME/.claude"
trap 'rm -rf "$HOME"' EXIT

describe "guarda destrutivo — comando executado vs texto que o contem"
assert_not_scratchpad

RESULT="$(python3 "$REPO/tests/unit/lib/run-destructive-cases.py" 2>&1)"
RC=$?

printf '%s\n' "$RESULT" | while IFS= read -r line; do
  case "$line" in
    OK*)   ok "${line#OK }" ;;
    FAIL*) bad "${line#FAIL }" ;;
    *)     [ -n "$line" ] && printf '    %s\n' "$line" ;;
  esac
done

FAILS="$(printf '%s\n' "$RESULT" | grep -c '^FAIL' || true)"
PASSES="$(printf '%s\n' "$RESULT" | grep -c '^OK' || true)"
LT_T_OK=$((LT_T_OK + PASSES))
LT_T_BAD=$((LT_T_BAD + FAILS))

end_describe
