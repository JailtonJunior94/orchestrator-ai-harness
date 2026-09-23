#!/usr/bin/env bash
# tests / unit / scripts / playbook-counts.test.sh
#
# validate-playbook-counts.sh e' o que permite exibir contagem em prosa. Se ele aprovar numero
# errado, a prosa volta a mentir com carimbo de verificada.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
. "$REPO/tests/unit/lib/assert.sh"

CHK="$REPO/scripts/validate-playbook-counts.sh"
W="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$W"' EXIT
HOOKS="$(python3 -c 'import json,sys;print(sum(len(m["hooks"]) for v in json.load(open(sys.argv[1]))["hooks"].values() for m in v))' "$REPO/plugins/lt/hooks/hooks.json")"
chk_rc() { bash "$CHK" "$W/doc.md" >/dev/null 2>&1; }

describe "contagem de total confere com o disco"

printf 'O plugin tem %s hooks.\n' "$HOOKS" > "$W/doc.md"
assert_exit_code 0 chk_rc
printf 'O plugin tem %s hooks.\n' "$((HOOKS + 1))" > "$W/doc.md"
assert_exit_code 1 chk_rc
assert_contains "$(bash "$CHK" "$W/doc.md" 2>&1)" "o disco tem $HOOKS" "diz o numero real"

describe "contagem de lista confere com os nomes enumerados"

printf 'Três skills: `a → b`, mais `c`.\n' > "$W/doc.md"
assert_exit_code 0 chk_rc
printf 'Quatro skills: `a → b`, mais `c`.\n' > "$W/doc.md"
assert_exit_code 1 chk_rc

describe "artigo nao e' contagem, e bloco de codigo nao conta"

printf 'Uma skill deste repo shipou assim.\n\n```\n99 hooks\n```\n' > "$W/doc.md"
assert_exit_code 0 chk_rc

end_describe
