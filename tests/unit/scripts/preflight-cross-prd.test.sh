#!/usr/bin/env bash
# tests / unit / scripts / preflight-cross-prd.test.sh
#
# O pre-voo do execute-all-tasks reprovava o PRD INTEIRO quando uma unica tarefa dependia de um
# bundle de outro repo ainda nao concluido. No bundle real que expos isso, so' a ultima de dez
# tarefas dependia do outro repo: as nove independentes ficavam impedidas de rodar pelo
# orquestrador, e a unica saida era executa-las a mao, uma a uma.
#
# Regra nova: dependencia externa AUSENTE ou NAO `done` e' atraso, nao corrupcao. Vira aviso, e
# `lt-sdd.sh waves` deixa a tarefa bloqueada com o motivo. Drift de hash no bundle externo e
# ciclo cross-PRD continuam reprovando tudo: ai' a cadeia de confianca esta rompida.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
. "$REPO/tests/unit/lib/assert.sh"

PLUGIN="$REPO/plugins/lt"
PRE="$PLUGIN/scripts/cycle/pre-execute-all-tasks.sh"
W="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$W"' EXIT
export CLAUDE_PLUGIN_ROOT="$PLUGIN"

mkdir -p "$W/api/.lt/specs/prd-feat" "$W/api/.lt" "$W/pipe"
( cd "$W/api" && git init -q ); ( cd "$W/pipe" && git init -q )
printf 'spec_repos:\n  feat-pipe: ../pipe\n' > "$W/api/.lt/config.yaml"
cat > "$W/api/.lt/specs/prd-feat/tasks.md" <<'EOF'
| # | Título | Status | Dependências | Paralelizável | Skills |
|---|---|---|---|---|---|
| 1.0 | a | pending | — | Não | — |
| 2.0 | b | pending | 1.0, feat-pipe/1.0 | Não | — |
EOF
# O pre-voo exige a cadeia PRD -> TechSpec -> tasks aprovada por hash (assert-approved). A
# fixture aprova a cadeia do bundle principal para que o teste exercite so' a regra cross-PRD.
A="$W/api/.lt/specs/prd-feat"
printf '# PRD\n\n- RF-01 a\n' > "$A/prd.md"
printf '# TechSpec\n' > "$A/techspec.md"
printf '\n## Cobertura de Requisitos\n\nRF-01 -> 1.0\n' >> "$A/tasks.md"
( cd "$W/api" && bash "$PLUGIN/scripts/lt-sdd.sh" sync-spec-hash "$A" >/dev/null 2>&1 )
for art in prd techspec tasks; do
  ( cd "$W/api" && bash "$PLUGIN/scripts/lt-sdd.sh" approve "$A" "$art" >/dev/null 2>&1 )
done
pre() { ( cd "$W/api" && bash "$PRE" feat 2>&1 ); }
pre_rc() { ( cd "$W/api" && bash "$PRE" feat >/dev/null 2>&1 ); }

P="$W/pipe/.lt/specs/prd-feat-pipe"
mk_pipe() {
  mkdir -p "$P"; printf '# PRD\n\n- RF-01 porte\n' > "$P/prd.md"
  local h; h="$(bash "$PLUGIN/scripts/lt-sdd.sh" hash "$P/prd.md")"
  printf '<!-- spec-hash-prd: %s -->\n\n| # | Título | Status | Dependências | Paralelizável | Skills |\n|---|---|---|---|---|---|\n| 1.0 | porte | %s | — | — | — |\n' "$h" "$1" > "$P/tasks.md"
}

describe "dependencia externa atrasada nao trava o PRD inteiro"

assert_exit_code 0 pre_rc
assert_contains "$(pre)" "WARN F18" "bundle externo ausente vira aviso"
assert_contains "$(pre)" "2.0" "o aviso nomeia a tarefa que vai ficar bloqueada"

mk_pipe pending
assert_exit_code 0 pre_rc
assert_contains "$(pre)" "status=pending" "tarefa externa nao done vira aviso com o status"

describe "corrupcao continua reprovando"

mk_pipe done
assert_exit_code 0 pre_rc
assert_not_contains "$(pre)" "F18" "externa done e integra nao gera aviso"
printf '\n- RF-02 mudou depois\n' >> "$P/prd.md"
assert_exit_code 1 pre_rc
assert_contains "$(pre)" "spec drift" "drift no bundle externo reprova"

end_describe
