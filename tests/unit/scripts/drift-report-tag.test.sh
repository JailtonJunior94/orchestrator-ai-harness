#!/usr/bin/env bash
# tests / unit / scripts / drift-report-tag.test.sh
#
# A secao de estado do guia afirma a "ultima tag semver". A regra falhou duas vezes em release
# real: contar a tag do proprio commit reprovava o CI do release; excluir a tag do HEAD ao GERAR
# (arvore suja, antes do commit) gravava a tag anterior a' anterior. Os tres momentos, provados:
#   1. gerar com arvore suja em cima do commit tagueado vX -> vX
#   2. conferir num commit novo, limpo e sem tag -> vX
#   3. conferir no commit que recebeu vY (limpo) -> vX (a propria tag nao conta)

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
. "$REPO/tests/unit/lib/assert.sh"

W="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$W"' EXIT
gitc() { git -c commit.gpgsign=false -c tag.gpgsign=false -c user.email=t@t -c user.name=t "$@"; }
tag_of() { ( cd "$W/r" && bash "$REPO/scripts/gen-drift-report.sh" 2>/dev/null | sed -n 's/^| ultima tag semver | \(.*\) |$/\1/p' ); }

mkdir -p "$W/r" && cp -R "$REPO/.claude-plugin" "$REPO/plugins" "$W/r/" 2>/dev/null
( cd "$W/r" && git init -q && gitc add -A && gitc commit -qm a && gitc tag -a v0.1.1 -m v0.1.1 )

describe "ultima tag semver da secao de estado"
printf 'x\n' > "$W/r/dirty.txt"
assert_eq "v0.1.1" "$(tag_of)" "arvore suja sobre o commit tagueado: gera para o proximo commit"
( cd "$W/r" && gitc add -A && gitc commit -qm b )
assert_eq "v0.1.1" "$(tag_of)" "commit novo, limpo e sem tag"
( cd "$W/r" && gitc tag -a v0.1.2 -m v0.1.2 )
assert_eq "v0.1.1" "$(tag_of)" "no commit da v0.1.2 a propria tag nao conta"
end_describe
