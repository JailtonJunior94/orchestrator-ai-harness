#!/usr/bin/env bash
# tests / unit / scripts / sdd-contracts.test.sh
#
# Contratos JSON versionados (config/schemas/) + corpus adversarial portado do harness de origem.
#
# O corpus afirma DUAS coisas por fixture: que ela e' rejeitada, e que e' rejeitada PELO MOTIVO
# que ela existe para provar — com exatamente um erro. Rejeicao pelo motivo errado e' falso verde:
# a fixture de "evidencia com ..", por exemplo, passava a ser rejeitada so por faltar `patch_ref`
# quando foi portada, e o teste de caminho nao estaria testando caminho nenhum.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
. "$REPO/tests/unit/lib/assert.sh"

SDD="$REPO/plugins/lt/lib/sdd.py"
FIX="$REPO/tests/fixtures/sdd-results"
W="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$W"' EXIT

describe "corpus adversarial: cada fixture reprova pelo proprio motivo"

expect_reject() {  # $1=fixture  $2=trecho esperado
  local kind=execution out n
  case "$1" in *review*) kind=review ;; esac
  out="$(python3 "$SDD" validate-result "$kind" "$FIX/$1" 2>&1)"
  if [ $? -ne 1 ]; then bad "$1 deveria reprovar"; return; fi
  n="$(printf '%s\n' "$out" | grep -c '^  - ')"
  case "$out" in
    *"$2"*) [ "$n" = "1" ] && ok "$1 reprova so por: $2" || bad "$1 reprova com $n erros (esperado 1): $out" ;;
    *) bad "$1 reprovou pelo motivo errado: $out" ;;
  esac
}

expect_reject integrity--01-short-base-sha.execution.reject.json '$.base_sha'
expect_reject integrity--02-short-patch.execution.reject.json '$.patch_sha256'
expect_reject integrity--03-short-final-state.execution.reject.json '$.final_state_sha256'
expect_reject integrity--04-invalid-attempt.execution.reject.json '$.attempt'
expect_reject paths--01-traversal-evidence.execution.reject.json 'escape de diretorio'
expect_reject paths--02-absolute-unix.execution.reject.json 'caminho relativo'
expect_reject paths--03-absolute-windows.execution.reject.json 'caminho relativo'
expect_reject paths--04-traversal-criterion.execution.reject.json 'escape de diretorio'
expect_reject proof--01-empty-tests.execution.reject.json '$.tests'
expect_reject proof--02-empty-criteria.execution.reject.json '$.criteria'
expect_reject proof--03-empty-evidence.execution.reject.json '$.evidence'
expect_reject proof--04-missing-test-digest.execution.reject.json 'output_sha256'
expect_reject review--01-invalid-verdict.review.reject.json '$.verdict'
expect_reject review--02-empty-tests.review.reject.json '$.tests'
expect_reject review--03-absolute-evidence.review.reject.json 'caminho relativo'
expect_reject review--04-extra-property.review.reject.json 'campos desconhecidos: extra'
expect_reject schema--01-version.execution.reject.json '$.schema_version'
expect_reject schema--02-unknown-field.execution.reject.json 'campos desconhecidos: injected'
expect_reject schema--03-missing-run.execution.reject.json 'run_id'
expect_reject schema--04-invalid-task-id.execution.reject.json '$.task_id'

N="$(find "$FIX" -name '*.reject.json' | wc -l | tr -d ' ')"
assert_eq "20" "$N" "o corpus tem as 20 fixtures adversariais (fixture nova exige asserção nova)"
assert_exit_code 0 python3 "$SDD" validate-result execution "$FIX/schema--99-control.execution.accept.json"

describe "regras condicionais do schema de execucao"

mut() {  # $1=saida  $2=expressao python sobre d
  python3 - "$FIX/schema--99-control.execution.accept.json" "$1" "$2" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
exec(sys.argv[3])
json.dump(d, open(sys.argv[2], "w"))
PY
}
mut "$W/r1.json" 'd["review_verdict"]="REJECTED"'
assert_contains "$(python3 "$SDD" validate-result execution "$W/r1.json" 2>&1)" "revisao aprovadora" "done com REJECTED reprova citando a regra"
mut "$W/r2.json" 'd["commit_sha"]="a"*40'
assert_contains "$(python3 "$SDD" validate-result execution "$W/r2.json" 2>&1)" "commit_patch_sha256" "selo pela metade reprova"
mut "$W/r3.json" 'd["status"]="failed"; d["review_verdict"]="REJECTED"; d["tests"][0]["exit_code"]=1'
assert_exit_code 0 python3 "$SDD" validate-result execution "$W/r3.json"
mut "$W/r4.json" 'd["review_verdict"]="approved"'
assert_exit_code 0 python3 "$SDD" validate-result execution "$W/r4.json"

describe "checkpoint"

printf '{"status":"done","report_path":".lt/specs/prd-x/1.0_execution_report.md","summary":"ok","timestamp":"2026-01-02T03:04:05Z"}' > "$W/cp.json"
assert_exit_code 0 python3 "$SDD" validate-result checkpoint "$W/cp.json"
printf '{"status":"done","report_path":"/abs/r.md","summary":"ok","timestamp":"2026-01-02T03:04:05Z"}' > "$W/cp2.json"
assert_exit_code 1 python3 "$SDD" validate-result checkpoint "$W/cp2.json"
printf '{"status":"done","report_path":"r.md","summary":"ok","timestamp":"ontem","extra":1}' > "$W/cp3.json"
OUT="$(python3 "$SDD" validate-result checkpoint "$W/cp3.json" 2>&1)"
assert_contains "$OUT" "timestamp" "timestamp fora de ISO-8601 reprova"
assert_contains "$OUT" "campos desconhecidos: extra" "campo extra no checkpoint reprova"

describe "palavra-chave de schema desconhecida falha alto"

cp -R "$REPO/plugins/lt" "$W/plugin"
python3 - "$W/plugin/config/schemas/review-result.schema.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d["properties"]["tests"]["maxItems"] = 1; json.dump(d, open(p, "w"))
PY
OUT="$(CLAUDE_PLUGIN_ROOT="$W/plugin" python3 "$W/plugin/lib/sdd.py" validate-result review "$FIX/review--02-empty-tests.review.reject.json" 2>&1)"
assert_contains "$OUT" "nao suportada: maxItems" "o validador recusa o que nao sabe cobrar, em vez de ignorar"
rm -f "$W/plugin/config/schemas/checkpoint.schema.json"
CLAUDE_PLUGIN_ROOT="$W/plugin" python3 "$W/plugin/lib/sdd.py" validate-result checkpoint "$W/cp.json" >/dev/null 2>&1
assert_eq "1" "$?" "schema ausente falha, nunca valida"

describe "validate-bugs"

printf '[{"id":"BUG-001","severity":"major","file":"src/a.go","line":3,"reproduction":"r","expected":"e","actual":"a"}]' > "$W/b1.json"
assert_exit_code 0 python3 "$SDD" validate-bugs "$W/b1.json"
printf '[{"id":"BUG-1","severity":"blocker","file":"src/a.go","line":0,"reproduction":"r","expected":"e","actual":"a"}]' > "$W/b2.json"
OUT="$(python3 "$SDD" validate-bugs "$W/b2.json" 2>&1)"
assert_contains "$OUT" '$[0].id' "id fora de BUG-NNN reprova"
assert_contains "$OUT" '$[0].severity' "severidade fora do enum reprova"
assert_contains "$OUT" '$[0].line' "linha < 1 reprova"
printf '[]' > "$W/b3.json"
assert_exit_code 1 python3 "$SDD" validate-bugs "$W/b3.json"
python3 -c 'import json;b={"id":"BUG-001","severity":"minor","file":"a","line":1,"reproduction":"r","expected":"e","actual":"a"};json.dump([b,b],open("'"$W"'/b4.json","w"))'
assert_contains "$(python3 "$SDD" validate-bugs "$W/b4.json" 2>&1)" "duplicado" "id repetido reprova"

describe "validate-sdd com contrato versionado"

git -C "$W" init -q repo
R="$W/repo"; P="$R/.lt/specs/prd-x"
mkdir -p "$P"
printf '# PRD\n- RF-01 algo\n' > "$P/prd.md"
printf '# TechSpec\n' > "$P/techspec.md"
mk_tasks() {  # $1=cabecalho extra
  printf '%s# Tasks\n| # | Tarefa | Status | Dependencias | Paralelizavel | Skills |\n|---|---|---|---|---|---|\n| 1.0 | X | pending | — | — | — |\n## Cobertura de Requisitos\n| Tarefa | Requisitos |\n|---|---|\n| 1.0 | RF-01 |\n' "$1" > "$P/tasks.md"
}
vsdd() { ( cd "$R" && python3 "$SDD" validate-sdd .lt/specs/prd-x "$@" 2>&1 ); }

mk_tasks ""
assert_contains "$(vsdd --contract)" "sdd-contract: v1 (sem marcador" "sem marcador o bundle continua v1"
assert_contains "$(vsdd)" "contrato v1" "bundle legado valida como antes"

mk_tasks "<!-- sdd-contract: v2 -->
"
assert_contains "$(vsdd)" "exige sdd-state.json" "v2 sem estado reprova"
( cd "$R" && python3 "$SDD" approve .lt/specs/prd-x prd >/dev/null )
assert_contains "$(vsdd --contract)" "sdd-contract: v2 (marcador" "marcador v2 detectado"
assert_contains "$(vsdd)" "contrato v2" "v2 com estado v2 integro passa"
printf 'mudou\n' >> "$P/prd.md"
assert_contains "$(vsdd)" "prd aprovado esta stale" "v2 reprova aprovacao que nao bate com os bytes"

mk_tasks "<!-- sdd-contract: v9 -->
"
assert_contains "$(vsdd)" "v9 desconhecido" "versao desconhecida falha em vez de validar como v1"
mk_tasks ""
assert_contains "$(vsdd --contract v1)" "pedido por --contract" "--contract v1 forca o contrato"

end_describe
