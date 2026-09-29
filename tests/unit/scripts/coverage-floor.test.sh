#!/usr/bin/env bash
# tests / unit / scripts / coverage-floor.test.sh
#
# Gate de cobertura de validate-task-evidence (R-TEST-002.1): piso de 70% por pacote tocado,
# delta nunca negativo e conferido contra after-before, n/a so' com diff sem codigo executavel.
# Cada caso existe para matar um mutante do gate: trocar `<` por `<=` no piso, checar so' o
# primeiro pacote, aceitar delta digitado a mao ou aceitar n/a com codigo alterado.
#
# O relatorio usa `Estado: blocked` para nao exigir a prova fisica do caminho `done`, que ja' tem
# teste proprio (done-path.test.sh). Aqui so' interessam as mensagens de cobertura.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
. "$REPO/tests/unit/lib/assert.sh"

EVID="$REPO/plugins/lt/scripts/validate-task-evidence.sh"
W="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$W"' EXIT

# $1 = linhas de Arquivos Alterados, $2 = corpo do bloco Coverage
mk_report() {
  printf '<!-- evidence-contract: v2 -->\n# Relatório\n\n- Estado: blocked\n\n## Arquivos Alterados\n%s\n\n## Coverage\n\n%s\n\n## Suposições\n- nenhuma\n' \
    "$1" "$2" > "$W/report.md"
}
cov() { bash "$EVID" "$W/report.md" 2>&1 | grep -i 'coverage' || true; }

describe "piso de 70% por pacote tocado"

mk_report "- app/service.go" "$(printf 'package=app\nbefore=60%%\nafter=69.9%%\ndelta=9.9%%')"
assert_contains "$(cov)" "abaixo do piso de 70% para package=app" "69.9% reprova"

mk_report "- app/service.go" "$(printf 'package=app\nbefore=60%%\nafter=70%%\ndelta=10%%')"
assert_eq "" "$(cov)" "70% exato passa sem mensagem de cobertura"

mk_report "- app/a.go" "$(printf 'package=a\nbefore=80%%\nafter=85%%\ndelta=5%%\npackage=b\nbefore=50%%\nafter=55%%\ndelta=5%%')"
assert_contains "$(cov)" "package=b" "o segundo pacote abaixo do piso reprova"
assert_not_contains "$(cov)" "package=a " "o pacote acima do piso nao e' acusado"

mk_report "- app/service.go" "$(printf 'package=app\nbefore=90%%\nafter=95%%\ndelta=5%%')"
assert_eq "" "$(cov)" "acima de 80% nao reprova (teto orientativo)"

end_describe

describe "regressao e consistencia do delta"

mk_report "- app/service.go" "$(printf 'package=app\nbefore=75.1%%\nafter=75%%\ndelta=-0.1%%')"
assert_contains "$(cov)" "coverage regression detectada" "delta=-0.1% reprova"

mk_report "- app/service.go" "$(printf 'package=app\nbefore=90%%\nafter=75%%\ndelta=0%%')"
assert_contains "$(cov)" "não confere com after-before" "delta que nao bate com after-before reprova"

mk_report "- app/service.go" "$(printf 'package=app\ndelta=0%%')"
assert_contains "$(cov)" "coverage after ausente" "formato antigo sem after reprova"

mk_report "- app/new.go" "$(printf 'package=novo\nbefore=n/a\nafter=72%%\ndelta=n/a')"
assert_eq "" "$(cov)" "pacote novo sem medida anterior passa com after acima do piso"

end_describe

describe "n/a so' com diff sem codigo executavel"

mk_report "- app/service.go" "$(printf 'package=n/a\nbefore=n/a\nafter=n/a\ndelta=n/a')"
assert_contains "$(cov)" "código executável alterado" "n/a com .go alterado reprova"

mk_report "$(printf -- '- docs/guia.md\n- config/app.yaml')" "$(printf 'package=n/a\nbefore=n/a\nafter=n/a\ndelta=n/a')"
assert_eq "" "$(cov)" "n/a com so' docs e config passa"

mk_report "- scripts/tool.zig" "$(printf 'package=n/a\nbefore=n/a\nafter=n/a\ndelta=n/a')"
assert_contains "$(cov)" "tool.zig" "extensao desconhecida conta como codigo (falha fechada)"

end_describe
