#!/usr/bin/env bash
# tests / unit / scripts / done-path.test.sh
#
# O caminho `done` nunca tinha sido percorrido inteiro por teste nenhum: relatorio ->
# validate-task-evidence -> seal-evidence -> post-execute-task. Percorrido num bundle real, ele
# nao fechava com a configuracao padrao. O validador exigia `sha=` igual ao `patch_sha256` (64
# hex) e o F35 exigia que o mesmo `sha=` fosse objeto do git (`git cat-file -e`). Nenhum valor
# satisfaz os dois: patch reprovava no F35, commit reprovava no validador.
#
# Decisao: `sha=` e' o SHA-256 do patch da tarefa. O F35 passa a provar duas coisas sobre ele,
# sem depender de commit (o harness nao commita, R-GOV-001): o arquivo de patch declarado ainda
# tem aquele hash, e as mudancas dele continuam aplicadas na arvore (revert e' detectado).

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
. "$REPO/tests/unit/lib/assert.sh"

PLUGIN="$REPO/plugins/lt"
W="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$W"' EXIT
export CLAUDE_PLUGIN_ROOT="$PLUGIN"

gitc() { git -c commit.gpgsign=false -c user.email=t@t -c user.name=t "$@"; }

# Monta um pacote `done` completo e valido no repo $W/$1.
mk_done() {
  local r="$W/$1" b=".lt/specs/prd-x"
  mkdir -p "$r/$b/.checkpoints" "$r/$b/evidence"
  ( cd "$r" && git init -q && printf 'x\n' > app.txt && git add app.txt && gitc commit -qm base )
  local base; base="$(git -C "$r" rev-parse HEAD)"
  printf 'y\n' >> "$r/app.txt"
  ( cd "$r" && git diff --binary "$base" > "$b/evidence/1.0.patch" )
  local patch tlog
  patch="$(shasum -a 256 "$r/$b/evidence/1.0.patch" | cut -d' ' -f1)"
  printf 'Tests: 3 passed\n' > "$r/$b/evidence/1.0-test.log"
  tlog="$(shasum -a 256 "$r/$b/evidence/1.0-test.log" | cut -d' ' -f1)"
  printf '# PRD\n\n- RF-01 algo\n' > "$r/$b/prd.md"
  printf '# TechSpec\n' > "$r/$b/techspec.md"
  printf '| # | Título | Status | Dependências | Paralelizável | Skills |\n|---|---|---|---|---|---|\n| 1.0 | X | done | — | — | — |\n' > "$r/$b/tasks.md"
  printf '# Tarefa 1.0\n\n## Critérios de Sucesso\n\n- teste passa\n\n## Testes da Tarefa\n' > "$r/$b/task-1.0-x.md"
  cat > "$r/$b/1.0_execution_result.json" <<EOF
{"schema_version":2,"run_id":"r1","task_id":"1.0","attempt":1,"status":"done","base_sha":"$base","patch_sha256":"$patch","patch_ref":"$b/evidence/1.0.patch","final_state_sha256":"$patch","tests":[{"command":"npm test","exit_code":0,"output_sha256":"$tlog"}],"criteria":[{"id":"c1","evidence_ref":"$b/evidence/1.0-test.log"}],"evidence":["$b/evidence/1.0-test.log","$b/evidence/1.0.patch"],"review_verdict":"APPROVED"}
EOF
  cat > "$r/$b/1.0_execution_report.md" <<EOF
<!-- evidence-contract: v2 -->
# Relatório de Execução de Tarefa

## Tarefa
- ID: 1.0
- Arquivo: task-1.0-x.md
- Estado: done

## Contexto Carregado
- PRD: $b/prd.md
- TechSpec: $b/techspec.md
- Requisito: RF-01

## Comandos Executados
- npm test -> 3 passed

## Arquivos Alterados
- app.txt

## Resultados de Validação
- Testes: pass
- Lint: pass
- Veredito do Revisor: APPROVED

## Critérios de Aceite
- teste passa -> comprovado: $b/evidence/1.0-test.log

## Execution Result

result_path=$b/1.0_execution_result.json

## Diff Reviewed

sha=$patch
verdict=APPROVED
tool=claude

## Coverage

package=app
delta=0%

## Suposições
- nenhuma

## Riscos Residuais
- nenhum
EOF
  printf '{"status":"done","report_path":"%s","summary":"ok","timestamp":"2026-09-23T00:00:00Z"}\n' \
    "$b/1.0_execution_report.md" > "$r/$b/.checkpoints/1.0.json"
  printf 'status: done\nreport_path: %s\nsummary: ok\n' "$b/1.0_execution_report.md" > "$r/y.yaml"
}
post() { ( cd "$W/$CASE" && bash "$PLUGIN/scripts/cycle/post-execute-task.sh" x 1.0 y.yaml 2>&1 ); }
post_rc() { ( cd "$W/$CASE" && bash "$PLUGIN/scripts/cycle/post-execute-task.sh" x 1.0 y.yaml >/dev/null 2>&1 ); }
R=".lt/specs/prd-x/1.0_execution_report.md"

describe "caminho done inteiro fecha com a configuracao padrao"

mk_done ok
CASE=ok
evid_rc() { bash "$PLUGIN/scripts/validate-task-evidence.sh" "$W/ok/$R" >/dev/null 2>&1; }
seal_rc() { bash "$PLUGIN/scripts/lt-sdd.sh" seal-evidence "$W/ok/$R" >/dev/null 2>&1; }
assert_exit_code 0 evid_rc
assert_exit_code 0 seal_rc
assert_exit_code 0 post_rc

describe "F35 prova o patch sem depender de commit"

mk_done adulterado
CASE=adulterado
printf 'lixo\n' >> "$W/adulterado/.lt/specs/prd-x/evidence/1.0.patch"
assert_exit_code 1 post_rc
assert_contains "$(post)" "F35" "patch adulterado depois do relatorio reprova no F35"

mk_done revertido
CASE=revertido
( cd "$W/revertido" && git checkout -q -- app.txt )
assert_exit_code 1 post_rc
assert_contains "$(post)" "nao esta mais aplicado" "mudanca revertida na arvore e' detectada"

mk_done commit40
CASE=commit40
C="$(git -C "$W/commit40" rev-parse HEAD)"
sed -i '' -e "s/^sha=.*/sha=$C/" "$W/commit40/$R" 2>/dev/null || sed -i -e "s/^sha=.*/sha=$C/" "$W/commit40/$R"
assert_exit_code 1 post_rc
assert_contains "$(post)" "patch_sha256" "sha= de commit e' recusado com a razao"

end_describe
