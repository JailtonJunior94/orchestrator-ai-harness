#!/usr/bin/env bash
# tests / unit / scripts / cost-baseline.test.sh
#
# check-cost-baseline.sh e' o ratchet do custo always-on. Roda aqui sobre saidas gravadas do
# `plugin details` (LT_DETAILS_OUTPUT), para nao depender do CLI; a medicao real roda no job de
# host do CI.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
. "$REPO/tests/unit/lib/assert.sh"

CHK="$REPO/scripts/check-cost-baseline.sh"
W="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$W"' EXIT
WANT="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["plugins"]["lt"]["always_on_tokens"])' "$REPO/docs/benchmarks/plugin-token-cost.json")"

details() { printf 'Projected token cost\n  Always-on:   ~%s tok   added to every session\n' "$1" > "$W/d.txt"; }
chk_rc() { LT_DETAILS_OUTPUT="$W/d.txt" bash "$CHK" >/dev/null 2>&1; }
chk() { LT_DETAILS_OUTPUT="$W/d.txt" bash "$CHK" 2>&1; }

describe "ratchet do custo always-on"

details "$(printf "%'d" "$WANT" 2>/dev/null || echo "$WANT")"
assert_exit_code 0 chk_rc
details "$((WANT + 1))"
assert_exit_code 1 chk_rc
assert_contains "$(chk)" "subiu" "subida reprova e diz o motivo"
details "$((WANT - 50))"
assert_exit_code 0 chk_rc
assert_contains "$(chk)" "Baixe a baseline" "descida passa e pede para baixar a baseline"
printf 'saida sem o numero\n' > "$W/d.txt"
assert_exit_code 1 chk_rc

end_describe
