#!/usr/bin/env bash
# tests / unit / scripts / sdd-seal-traceability.test.sh
#
# Selo de commit opcional (seal-evidence --commit/--verify) e rastreabilidade requisito ->
# tarefa -> evidencia (check-traceability), num bundle `done` montado de verdade: repo git, patch
# real, execution-result v2 apontado por `result_path=` no relatorio.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
. "$REPO/tests/unit/lib/assert.sh"

SDD="$REPO/plugins/lt/lib/sdd.py"
W="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$W"' EXIT
B=".lt/specs/prd-x"
gitc() { git -c commit.gpgsign=false -c user.email=t@t -c user.name=t "$@"; }

# Bundle done com base_sha = $2 (commit ou arvore).
mk_done() {  # $1=repo  $2=commit|tree
  local r="$W/$1"
  mkdir -p "$r/$B/evidence"
  ( cd "$r" && git init -q && printf 'x\n' > app.txt && git add app.txt && gitc commit -qm base )
  local base; base="$(git -C "$r" rev-parse HEAD)"
  [ "$2" = "tree" ] && base="$(cd "$r" && python3 "$SDD" snapshot)"
  printf 'y\n' >> "$r/app.txt"
  ( cd "$r" && git diff --binary > "$B/evidence/1.0.patch" )
  local patch tlog
  patch="$(shasum -a 256 "$r/$B/evidence/1.0.patch" | cut -d' ' -f1)"
  printf 'ok\n' > "$r/$B/evidence/1.0-test.log"
  tlog="$(shasum -a 256 "$r/$B/evidence/1.0-test.log" | cut -d' ' -f1)"
  printf '# PRD\n\n- RF-01 algo\n- RF-02 outro\n' > "$r/$B/prd.md"
  printf '# Tasks\n| # | Tarefa | Status | Dependencias | Paralelizavel | Skills |\n|---|---|---|---|---|---|\n| 1.0 | X | done | — | — | — |\n| 2.0 | Y | pending | 1.0 | — | — |\n\n## Cobertura de Requisitos\n\n| Tarefa | Requisitos |\n|---|---|\n| 1.0 | RF-01 |\n| 2.0 | RF-02 |\n' > "$r/$B/tasks.md"
  cat > "$r/$B/1.0_execution_result.json" <<EOF
{"schema_version":2,"run_id":"r1","task_id":"1.0","attempt":1,"status":"done","base_sha":"$base","patch_sha256":"$patch","patch_ref":"$B/evidence/1.0.patch","final_state_sha256":"$patch","tests":[{"command":"make test","exit_code":0,"output_sha256":"$tlog"}],"criteria":[{"id":"c1","evidence_ref":"$B/evidence/1.0-test.log"}],"evidence":["$B/evidence/1.0-test.log","$B/evidence/1.0.patch"],"review_verdict":"APPROVED"}
EOF
  cat > "$r/$B/1.0_execution_report.md" <<EOF
<!-- evidence-contract: v2 -->
# Relatório de Execução de Tarefa

## Tarefa
- ID: 1.0
- Requisito: RF-01

## Comandos Executados
- make test -> ok

## Arquivos Alterados
- app.txt

## Resultados de Validação
- Testes: pass

## Critérios de Aceite
- teste passa -> comprovado: $B/evidence/1.0-test.log

## Execution Result

result_path=$B/1.0_execution_result.json
EOF
}
seal() { local r="$1"; shift; ( cd "$W/$r" && python3 "$SDD" seal-evidence "$B/1.0_execution_report.md" "$@" 2>&1 ); }
seal_rc() { local r="$1"; shift; ( cd "$W/$r" && python3 "$SDD" seal-evidence "$B/1.0_execution_report.md" "$@" >/dev/null 2>&1 ); }
field() { python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get(sys.argv[2]))' "$@"; }

describe "seal-evidence sem flags continua so conferindo secoes"
mk_done c commit
assert_exit_code 0 seal_rc c
assert_eq "None" "$(field "$W/c/$B/1.0_execution_result.json" commit_sha)" "sem --commit nada e' gravado"

describe "seal-evidence --commit sobre base commit"
( cd "$W/c" && git add -A && gitc commit -qm trabalho )
OUT="$(seal c --commit HEAD)"
assert_contains "$OUT" "selada no commit" "selo gravado"
HEAD_SHA="$(git -C "$W/c" rev-parse HEAD)"
assert_eq "$HEAD_SHA" "$(field "$W/c/$B/1.0_execution_result.json" commit_sha)" "commit_sha e' o HEAD resolvido"
EXPECT="$(git -C "$W/c" diff --binary "$(git -C "$W/c" rev-parse HEAD~1)" HEAD -- . ":(exclude)$B" | shasum -a 256 | cut -d' ' -f1)"
assert_eq "$EXPECT" "$(field "$W/c/$B/1.0_execution_result.json" commit_patch_sha256)" "digest = diff base..commit sem o bundle"
assert_exit_code 0 python3 "$SDD" validate-result execution "$W/c/$B/1.0_execution_result.json"
assert_contains "$(seal c --verify)" "--verify OK" "verify recomputa e confere"
assert_contains "$(seal c --commit HEAD)" "ja selada" "selar duas vezes e' recusado"
python3 - "$W/c/$B/1.0_execution_result.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d["commit_patch_sha256"] = "0" * 64; json.dump(d, open(p, "w"))
PY
assert_contains "$(seal c --verify)" "diverge do selo" "selo adulterado reprova no verify"

describe "commit que nao descende da base e' recusado"
mk_done orfao commit
( cd "$W/orfao" && git checkout -q --orphan outra && git add -A && gitc commit -qm fora )
assert_contains "$(seal orfao --commit HEAD)" "nao descende" "historia paralela nao sela"

describe "base como arvore de snapshot exige --base"
mk_done arv tree
BASE_COMMIT="$(git -C "$W/arv" rev-parse HEAD)"
( cd "$W/arv" && git add -A && gitc commit -qm trabalho )
assert_contains "$(seal arv --commit HEAD)" "--base" "sem --base, arvore nao prova descendencia"
assert_contains "$(seal arv --commit HEAD --base "$BASE_COMMIT")" "selada no commit" "com --base, sela"
assert_contains "$(seal arv --verify)" "--verify OK" "verify nao precisa do --base"

describe "selo so' de resultado done"
mk_done falho commit
python3 - "$W/falho/$B/1.0_execution_result.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d["status"] = "failed"; d["review_verdict"] = "REJECTED"; json.dump(d, open(p, "w"))
PY
( cd "$W/falho" && git add -A && gitc commit -qm x )
assert_contains "$(seal falho --commit HEAD)" "apenas resultado done" "failed nao sela"

describe "check-traceability"
trace() { ( cd "$W/$1" && python3 "$SDD" check-traceability "$B" 2>&1 ); }
trace_rc() { ( cd "$W/$1" && python3 "$SDD" check-traceability "$B" >/dev/null 2>&1 ); }
mk_done t commit
assert_contains "$(trace t)" "cadeia de rastreabilidade verificada" "bundle integro passa"
assert_exit_code 0 trace_rc t

printf '\n- RF-03 novo\n' >> "$W/t/$B/prd.md"
assert_contains "$(trace t)" "requisito_sem_tarefa: RF-03" "RF do PRD sem tarefa e' ruptura"
assert_exit_code 1 trace_rc t

mk_done o commit
printf '| 2.0 | RF-09 |\n' >> "$W/o/$B/tasks.md"
assert_contains "$(trace o)" "requisito_orfao: RF-09" "RF na cobertura sem PRD e' orfao"

mk_done e commit
sed -i '' -e 's/- Requisito: RF-01/- Requisito: RF-07/' "$W/e/$B/1.0_execution_report.md" 2>/dev/null \
  || sed -i -e 's/- Requisito: RF-01/- Requisito: RF-07/' "$W/e/$B/1.0_execution_report.md"
OUT="$(trace e)"
assert_contains "$OUT" "evidencia_orfa: 1.0 cita RF-07" "evidencia citando RF inexistente e' orfa"
assert_contains "$OUT" "requisito_sem_evidencia: RF-01" "RF atribuido sem evidencia e' ruptura"

mk_done m commit
rm "$W/m/$B/1.0_execution_report.md"
assert_contains "$(trace m)" "tarefa_sem_relatorio: 1.0" "done sem relatorio e' ruptura"

mk_done p commit
sed -i '' -e 's/| 1.0 | X | done |/| 1.0 | X | pending |/' "$W/p/$B/tasks.md" 2>/dev/null \
  || sed -i -e 's/| 1.0 | X | done |/| 1.0 | X | pending |/' "$W/p/$B/tasks.md"
assert_contains "$(trace p)" "evidencia nao confrontada" "sem tarefa done o comando diz que nao confrontou evidencia"

( cd "$W/t" && python3 "$SDD" check-traceability .lt/specs/prd-nada >/dev/null 2>&1 )
assert_eq "2" "$?" "bundle inexistente nao e' verde (exit 2, erro de uso)"

end_describe
