#!/usr/bin/env bash
# tests / unit / scripts / sdd-gate-false-green.test.sh
#
# Dois gates davam resultado errado em silencio, os dois achados validando um bundle real
# (lt-api, prd-severidade-criticidade-alarmes):
#
# 1. `validate-sdd` casava requisito com `\b(RF|REQ)-\d+\b`. Identificador com sufixo de letra
#    (`RF-09b`, `RF-30a`) nao casa essa regex em posicao nenhuma: nao ha fronteira de palavra
#    entre o digito e a letra. O PRD tinha quatro desses sem tarefa e o gate respondia OK.
#
# 2. `validate-skill-prerequisites.sh` exigia `node-implementation` para qualquer `.ts`. A camada
#    de linguagem nao vem nesta versao do plugin, e as proprias skills mandam seguir sem ela:
#    o gate bloqueava toda tarefa TypeScript de todo repo consumidor.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
. "$REPO/tests/unit/lib/assert.sh"

SDD="$REPO/plugins/lt/lib/sdd.py"
PREREQ="$REPO/plugins/lt/scripts/validate-skill-prerequisites.sh"
W="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$W"' EXIT

mk_bundle() {
  mkdir -p "$W/$1/.lt/specs/prd-x"
  ( cd "$W/$1" && git init -q )
  printf '# PRD\n\n- RF-09 — nivel corrente\n- RF-09b — nivel congelado\n- REQ-30a — cursor\n' \
    > "$W/$1/.lt/specs/prd-x/prd.md"
  {
    printf '| # | Título | Status | Dependências | Paralelizável | Skills |\n'
    printf '|---|---|---|---|---|---|\n'
    printf '| 1.0 | Uma | pending | — | — | — |\n\n'
    printf '## Cobertura de Requisitos\n\n| Tarefa | Requisitos |\n|---|---|\n'
    printf '| 1.0 | %s |\n' "$2"
  } > "$W/$1/.lt/specs/prd-x/tasks.md"
}
validate() { ( cd "$W/$1" && python3 "$SDD" validate-sdd .lt/specs/prd-x 2>&1 ); }
validate_rc() { ( cd "$W/$CASE" && python3 "$SDD" validate-sdd .lt/specs/prd-x >/dev/null 2>&1 ); }

describe "validate-sdd enxerga requisito com sufixo de letra"

mk_bundle falta "RF-09"
CASE=falta
assert_exit_code 1 validate_rc
OUT="$(validate falta)"
assert_contains "$OUT" "RF-09b" "nomeia o requisito com sufixo que ficou sem tarefa"
assert_contains "$OUT" "REQ-30a" "vale tambem para o prefixo REQ"

mk_bundle completo "RF-09, RF-09b, REQ-30a"
CASE=completo
assert_exit_code 0 validate_rc

# O sufixo nao pode fazer RF-09b contar como cobertura de RF-09: sao requisitos distintos.
mk_bundle so_sufixo "RF-09b, REQ-30a"
CASE=so_sufixo
assert_exit_code 1 validate_rc
assert_contains "$(validate so_sufixo)" "RF-09" "RF-09b nao cobre RF-09"

describe "validate-skill-prerequisites respeita a camada de linguagem opcional por linguagem"

mk_skill() {
  mkdir -p "$W/$1/skills/$2"
  printf -- '---\nname: %s\nmetadata:\n  category: %s\n---\n' "$2" "$3" > "$W/$1/skills/$2/SKILL.md"
  if [ "${4:-}" = "index" ]; then
    mkdir -p "$W/$1/skills/$2/references"
    printf 'refs: []\n' > "$W/$1/skills/$2/references/INDEX.yaml"
  fi
}
prereq() { AGENTS_ROOT="$W/$ROOT" bash "$PREREQ" "$@"; }

mk_skill sem_camada review governance
ROOT=sem_camada
assert_exit_code 0 prereq src/a.ts
ERR="$(AGENTS_ROOT="$W/sem_camada" bash "$PREREQ" src/a.ts 2>&1 >/dev/null)"
assert_contains "$ERR" "camada de linguagem" "avisa que seguiu sem a camada, em vez de calar"

# A camada e' opcional por linguagem: so' a skill de Go instalada nao pode bloquear tarefa de
# outra linguagem. Esse era o defeito do gate que tratava a camada como bloco unico.
mk_skill com_camada go-guideline language index
ROOT=com_camada
assert_exit_code 0 prereq src/a.ts
ERR="$(AGENTS_ROOT="$W/com_camada" bash "$PREREQ" src/a.ts 2>&1 >/dev/null)"
assert_contains "$ERR" "node-implementation" "avisa qual linguagem seguiu sem skill"
assert_exit_code 0 prereq cmd/main.go
assert_exit_code 0 prereq cmd/main.go src/a.ts app/x.py

mk_skill com_node node-implementation language index
ROOT=com_node
assert_exit_code 0 prereq src/a.ts

# Skill instalada sem INDEX.yaml e' instalacao quebrada: o agente nao teria o mapa de referencias.
mk_skill go_quebrada go-guideline language
ROOT=go_quebrada
assert_exit_code 1 prereq cmd/main.go
assert_exit_code 0 prereq src/a.ts
warn_rc() { AGENTS_ROOT="$W/go_quebrada" PREREQ_MODE=warn bash "$PREREQ" cmd/main.go 2>/dev/null; }
assert_exit_code 0 warn_rc

# Sem AGENTS_ROOT, o cabecalho promete CLAUDE_PLUGIN_ROOT antes de pwd; o codigo usava so' pwd.
# Em $W nao ha skills (seguiria com aviso, exit 0); so' lendo CLAUDE_PLUGIN_ROOT o gate enxerga a
# instalacao quebrada e sai 1.
plugin_root_rc() { ( cd "$W" && CLAUDE_PLUGIN_ROOT="$W/go_quebrada" bash "$PREREQ" cmd/main.go >/dev/null 2>&1 ) ; }
assert_exit_code 1 plugin_root_rc

describe "validate-task-evidence confere o requisito citado pelo identificador inteiro"

EVID="$REPO/plugins/lt/scripts/validate-task-evidence.sh"
mkdir -p "$W/evid"
printf '# PRD\n\n- RF-10 — dez\n- RF-09b — congelado\n' > "$W/evid/prd.md"
mk_report() {
  printf '<!-- evidence-contract: v2 -->\n# Relatório\n\n## Contexto Carregado\n\nPRD: %s\nTechSpec: n/a\n\nEstado: blocked\nCita: %s\n' \
    "$W/evid/prd.md" "$1" > "$W/evid/report.md"
}
evid() { bash "$EVID" "$W/evid/report.md" 2>&1; }

mk_report "RF-1"
assert_contains "$(evid)" "requisito RF-1 citado" "RF-1 nao e' encontrado so' porque o PRD tem RF-10"

mk_report "RF-09b"
assert_not_contains "$(evid)" "requisito RF-09b" "RF-09b existente no PRD nao e' acusado"
assert_not_contains "$(evid)" "requisito RF-09 " "o sufixo nao e' cortado na extracao"

mk_report "RF-09c"
assert_contains "$(evid)" "requisito RF-09c citado" "RF-09c inexistente e' acusado mesmo com RF-09b no PRD"

end_describe
