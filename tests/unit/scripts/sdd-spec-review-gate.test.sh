#!/usr/bin/env bash
# tests / unit / scripts / sdd-spec-review-gate.test.sh
#
# Dial `spec_review` (R-SPEC-001): `optional` (default) nao muda o approve; `required` exige
# `review-<artefato>.md` no bundle para prd e techspec, e nunca para tasks.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
. "$REPO/tests/unit/lib/assert.sh"

SDD="$REPO/plugins/lt/lib/sdd.py"
export HOME="$(mktemp -d)"
export CLAUDE_CONFIG_DIR="$HOME/.claude"
W="$(mktemp -d)"
trap 'rm -rf "$W" "$HOME"' EXIT
git -C "$W" init -q
P="$W/.lt/specs/prd-x"
mkdir -p "$P"
printf '# PRD\nRF-01 teste\n' > "$P/prd.md"
printf '<!-- spec-hash-prd: %064d -->\n# TechSpec\n' 0 > "$P/techspec.md"
printf '<!-- spec-hash-prd: %064d -->\n<!-- spec-hash-techspec: %064d -->\n# Tasks\n| # | Tarefa | Status | Dependencias | Paralelizavel | Skills |\n|---|---|---|---|---|---|\n| 1.0 | Fazer | pending | — | — | — |\n## Cobertura de Requisitos\nRF-01\n' 0 0 > "$P/tasks.md"
( cd "$W" && python3 "$SDD" sync-spec-hash "$P" >/dev/null )

describe "spec_review: gate de revisao de contexto zero no approve"
assert_not_scratchpad

# --- default (sem chave): approve segue sem relatorio ---
( cd "$W" && python3 "$SDD" approve "$P" prd >/dev/null 2>&1 )
assert_eq "0" "$?" "sem spec_review no config, prd aprova sem review-prd.md"

# --- required: techspec sem relatorio e' recusada com exit 3 e mensagem util ---
printf 'squad: x\nspec_review: required\n' > "$W/.lt/config.yaml"
out="$(cd "$W" && python3 "$SDD" approve "$P" techspec 2>&1)"; rc=$?
assert_eq "3" "$rc" "required sem review-techspec.md recusa com exit 3"
assert_contains "$out" "review-techspec.md" "a recusa diz qual arquivo falta"
assert_contains "$out" "spec_review" "a recusa diz qual chave governa"

# --- required: com relatorio, aprova ---
printf '# Revisão de contexto zero — techspec\n## Achados\nSem achados\n' > "$P/review-techspec.md"
( cd "$W" && python3 "$SDD" approve "$P" techspec >/dev/null 2>&1 )
assert_eq "0" "$?" "required com review-techspec.md aprova"

# --- required nunca exige relatorio para tasks ---
( cd "$W" && python3 "$SDD" approve "$P" tasks >/dev/null 2>&1 )
assert_eq "0" "$?" "tasks aprova sem review-tasks.md mesmo em required"

# --- valor com typo conta como optional: config quebrado nao trava o ciclo ---
printf 'spec_review: requerido\n' > "$W/.lt/config.yaml"
printf '\nmudou\n' >> "$P/prd.md"
( cd "$W" && python3 "$SDD" approve "$P" prd >/dev/null 2>&1 )
assert_eq "0" "$?" "valor desconhecido de spec_review nao bloqueia"

end_describe
