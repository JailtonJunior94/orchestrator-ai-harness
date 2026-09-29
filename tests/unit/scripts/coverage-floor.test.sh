#!/usr/bin/env bash
# tests / unit / scripts / coverage-floor.test.sh
#
# Gate de cobertura R-TEST-002.1 (lib/coverage-gate.sh): piso de 70% por pacote tocado, delta
# nunca negativo e conferido contra after-before, prova de medicao (comando de cobertura + log com o
# numero de after) e n/a so' com diff sem codigo executavel. Cada caso existe para matar um mutante
# do gate: trocar `<` por `<=` no piso, checar so' o primeiro pacote, aceitar delta digitado a mao,
# aceitar numero sem medicao ou aceitar n/a com codigo alterado.
#
# A lib e' testada direto; depois, um caso por validador (tarefa, bugfix, refactor) prova que os
# tres a chamam e que bugfix/refactor so' a exigem quando houve mudanca de codigo.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
. "$REPO/tests/unit/lib/assert.sh"

PLUGIN="$REPO/plugins/lt"
. "$PLUGIN/lib/coverage-gate.sh"
W="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$W"' EXIT
( cd "$W" && git init -q )

CMD="- go test -coverprofile=cover.out ./... -> ok"

# $1 = Arquivos Alterados, $2 = Comandos Executados, $3 = corpo do bloco Coverage
mk_report() {
  printf '# Relatório\n\n## Arquivos Alterados\n%s\n\n## Comandos Executados\n%s\n\n## Coverage\n\n%s\n\n## Suposições\n- nenhuma\n' \
    "$1" "$2" "$3" > "$W/report.md"
}
log() { printf '%s\n' "$2" > "$W/$1"; }
cov() { lt_coverage_check "$W/report.md" 2>&1 || true; }
grp() { printf 'package=%s\nbefore=%s\nafter=%s\ndelta=%s\nlog=%s' "$@"; }

log cov-70.log "ok  app  coverage: 70.0% of statements"
log cov-69.log "ok  app  coverage: 69.9% of statements"
log cov-95.log "ok  app  coverage: 95.0% of statements"

describe "piso de 70% por pacote tocado"

mk_report "- app/service.go" "$CMD" "$(grp app 60% 69.9% 9.9% cov-69.log)"
assert_contains "$(cov)" "abaixo do piso de 70% para package=app" "69.9% reprova"

mk_report "- app/service.go" "$CMD" "$(grp app 60% 70% 10% cov-70.log)"
assert_eq "" "$(cov)" "70% exato, medido e com log passa"

mk_report "- app/a.go" "$CMD" "$(grp a 60% 95% 35% cov-95.log; printf '\n'; grp b 60% 69.9% 9.9% cov-69.log)"
assert_contains "$(cov)" "package=b" "o segundo pacote abaixo do piso reprova"
assert_not_contains "$(cov)" "package=a " "o pacote acima do piso nao e' acusado"

mk_report "- app/service.go" "$CMD" "$(grp app 90% 95% 5% cov-95.log)"
assert_eq "" "$(cov)" "acima de 80% nao reprova (teto orientativo)"

end_describe

describe "regressao e consistencia do delta"

mk_report "- app/service.go" "$CMD" "$(grp app 70.1% 70% -0.1% cov-70.log)"
assert_contains "$(cov)" "coverage regression detectada" "delta=-0.1% reprova"

mk_report "- app/service.go" "$CMD" "$(grp app 90% 70% 0% cov-70.log)"
assert_contains "$(cov)" "não confere com after-before" "delta que nao bate com after-before reprova"

mk_report "- app/service.go" "$CMD" "$(printf 'package=app\ndelta=0%%')"
assert_contains "$(cov)" "coverage after ausente" "formato antigo sem after reprova e diz o formato esperado"
assert_contains "$(cov)" "log=" "a mensagem do formato antigo cita log="

mk_report "- app/new.go" "$CMD" "$(grp novo n/a 70% n/a cov-70.log)"
assert_eq "" "$(cov)" "pacote novo sem medida anterior passa com after no piso"

end_describe

describe "prova de medicao"

mk_report "- app/service.go" "- go test ./... -> ok" "$(grp app 60% 70% 10% cov-70.log)"
assert_contains "$(cov)" "sem comando de cobertura" "numero sem comando de cobertura reprova"

mk_report "- app/service.go" "$CMD" "$(printf 'package=app\nbefore=60%%\nafter=70%%\ndelta=10%%')"
assert_contains "$(cov)" "log= ausente" "numero sem log= reprova"

mk_report "- app/service.go" "$CMD" "$(grp app 60% 70% 10% nao-existe.log)"
assert_contains "$(cov)" "inexistente ou vazio" "log= inexistente reprova"

mk_report "- app/service.go" "$CMD" "$(grp app 60% 75% 15% cov-70.log)"
assert_contains "$(cov)" "não aparece em log=" "after que nao aparece no log reprova (numero inventado)"

mk_report "- app/service.go" "$CMD" "$(grp app 60% 70% 10% ../fora.log)"
assert_contains "$(cov)" "fora do repositório" "log= fora do repositorio reprova"

end_describe

describe "n/a so' com diff sem codigo executavel"

NA="$(printf 'package=n/a\nbefore=n/a\nafter=n/a\ndelta=n/a')"
mk_report "- app/service.go" "" "$NA"
assert_contains "$(cov)" "código executável alterado" "n/a com .go alterado reprova"

mk_report "$(printf -- '- docs/guia.md\n- config/app.yaml')" "" "$NA"
assert_eq "" "$(cov)" "n/a com so' docs e config passa, sem exigir comando nem log"

mk_report "- scripts/tool.zig" "" "$NA"
assert_contains "$(cov)" "tool.zig" "extensao desconhecida conta como codigo (falha fechada)"

end_describe

describe "os tres validadores usam o gate"

TASK="$PLUGIN/scripts/validate-task-evidence.sh"
printf '<!-- evidence-contract: v2 -->\n# R\n\n- Estado: blocked\n\n## Arquivos Alterados\n- app/x.go\n\n## Comandos Executados\n%s\n\n## Coverage\n\n%s\n' \
  "$CMD" "$(grp app 60% 69.9% 9.9% cov-69.log)" > "$W/task.md"
assert_contains "$(bash "$TASK" "$W/task.md" 2>&1)" "abaixo do piso" "validate-task-evidence reprova abaixo do piso"

BUGFIX="$PLUGIN/scripts/validate-bugfix-evidence.sh"
mk_bugfix() {
  printf '# Relatorio de Bugfix\n\n- Total de bugs no escopo: 1\n- Corrigidos: %s\n- Testes de regressao adicionados: %s\n- Pendentes: nenhum\n- Estado final: done\n\n## Bugs\n- ID: BUG-001\n- Origem: RF-01\n- Estado: fixed\n- Causa raiz: x\n- Arquivos alterados: app/x.go\n- Teste de regressao: TestX\n- Validacao: ok\n\n## Comandos Executados\n%s\n\n%s\n## Riscos Residuais\n- nenhum\n' \
    "$1" "$1" "$CMD" "$2" > "$W/bugfix.md"
}
mk_bugfix 1 "$(printf '## Coverage\n\n'; grp app 60% 69.9% 9.9% cov-69.log; printf '\n')"
assert_contains "$(bash "$BUGFIX" --no-rf "$W/bugfix.md" 2>&1)" "abaixo do piso" "bugfix com correcao reprova abaixo do piso"
mk_bugfix 1 ""
assert_contains "$(bash "$BUGFIX" --no-rf "$W/bugfix.md" 2>&1)" "sem package=" "bugfix com correcao exige o bloco Coverage"
mk_bugfix 0 ""
assert_not_contains "$(bash "$BUGFIX" --no-rf "$W/bugfix.md" 2>&1)" "overage" "bugfix sem correcao nao cobra cobertura"

REFACTOR="$PLUGIN/scripts/validate-refactor-evidence.sh"
mk_refactor() {
  printf '# Relatório de Refatoração\n\n## Escopo\n- Alvo: app\n- Modo: %s\n- Estado: done\n\n## Invariantes Preservadas\n- x\n\n## Mudanças Aplicadas\n- x\n\n## Arquivos Alterados\n- app/x.go\n\n## Comandos Executados\n%s\n\n## Coverage\n\n%s\n\n## Resultados de Validação\n- Testes: pass\n- Lint: pass\n- Veredito do Revisor: APPROVED\n\n## Riscos Residuais\n- nenhum\n' \
    "$1" "$CMD" "$2" > "$W/refactor.md"
}
mk_refactor execution "$(grp app 60% 69.9% 9.9% cov-69.log)"
assert_contains "$(bash "$REFACTOR" "$W/refactor.md" 2>&1)" "abaixo do piso" "refactor em execution reprova abaixo do piso"
mk_refactor execution "$(grp app 60% 70% 10% cov-70.log)"
assert_contains "$(bash "$REFACTOR" "$W/refactor.md" 2>&1)" "aprovada" "refactor em execution no piso e medido aprova"
mk_refactor advisory ""
assert_not_contains "$(bash "$REFACTOR" "$W/refactor.md" 2>&1)" "overage" "refactor advisory nao cobra cobertura"

end_describe
