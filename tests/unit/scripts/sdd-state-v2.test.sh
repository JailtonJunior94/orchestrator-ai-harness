#!/usr/bin/env bash
# tests / unit / scripts / sdd-state-v2.test.sh
#
# Estado SDD v2: bundle novo nasce v2, v1 continua legivel, migrate-sdd converte com backup
# exclusivo SEM aprovar por decreto, rollback-sdd devolve exatamente o arquivo anterior, e
# orchestrate so' registra execucao sobre cadeia aprovada — idempotente por run_id.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
. "$REPO/tests/unit/lib/assert.sh"

SDD="$REPO/plugins/lt/lib/sdd.py"
W="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$W"' EXIT

mk_bundle() {  # $1=repo
  git -C "$W" init -q "$1"
  local p="$W/$1/.lt/specs/prd-x"
  mkdir -p "$p"
  printf '# PRD\n- RF-01 algo\n' > "$p/prd.md"
  printf '# TechSpec\n' > "$p/techspec.md"
  printf '# Tasks\n| # | Tarefa | Status | Dependencias | Paralelizavel | Skills |\n|---|---|---|---|---|---|\n| 1.0 | A | pending | — | — | — |\n| 2.0 | B | pending | 1.0 | — | — |\n## Cobertura de Requisitos\n| Tarefa | Requisitos |\n|---|---|\n| 1.0 | RF-01 |\n' > "$p/tasks.md"
}
sdd() { local r="$1"; shift; ( cd "$W/$r" && python3 "$SDD" "$@" ); }
field() { python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));exec("print("+sys.argv[2]+")")' "$@"; }

describe "bundle novo nasce em v2"
mk_bundle novo
S="$W/novo/.lt/specs/prd-x/sdd-state.json"
sdd novo approve .lt/specs/prd-x prd >/dev/null
assert_eq "2" "$(field "$S" 'd["schema_version"]')" "schema_version 2"
assert_eq "True" "$(field "$S" 'd["artifacts"]["prd"]["approved"]')" "approved acompanha o status"
assert_eq "approved" "$(field "$S" 'd["events"][-1]["action"]')" "aprovacao vira evento"
sdd novo invalidate .lt/specs/prd-x --from prd >/dev/null
assert_eq "False" "$(field "$S" 'd["artifacts"]["prd"]["approved"]')" "invalidate derruba a flag"
assert_eq "invalidated" "$(field "$S" 'd["events"][-1]["action"]')" "invalidacao vira evento"

describe "v1 continua legivel e intocado ate a migracao"
mk_bundle legado
P="$W/legado/.lt/specs/prd-x"
H="$(python3 "$SDD" hash "$P/prd.md")"
printf '{"schema_version": 1, "artifacts": {"prd": {"status": "approved", "hash": "%s"}}}\n' "$H" > "$P/sdd-state.json"
cp "$P/sdd-state.json" "$W/v1.orig"
sdd legado approve .lt/specs/prd-x techspec >/dev/null
assert_eq "1" "$(field "$P/sdd-state.json" 'd["schema_version"]')" "approve em v1 nao migra por efeito colateral"
assert_eq "approved" "$(field "$P/sdd-state.json" 'd["artifacts"]["techspec"]["status"]')" "approve em v1 segue funcionando"
cp "$P/sdd-state.json" "$W/v1.before-migrate"

describe "migrate-sdd"
OUT="$(sdd legado migrate-sdd .lt/specs/prd-x --run-id mig-1 --dry-run)"
assert_contains "$OUT" "dry-run" "dry-run anuncia que nao escreveu"
assert_eq "1" "$(field "$P/sdd-state.json" 'd["schema_version"]')" "dry-run nao escreve"
sdd legado migrate-sdd .lt/specs/prd-x --run-id mig-1 >/dev/null
assert_eq "2" "$(field "$P/sdd-state.json" 'd["schema_version"]')" "migrado para v2"
assert_file_exists "$P/.sdd-state.mig-1.legacy.json" "backup gravado"
assert_eq "$(cat "$W/v1.before-migrate")" "$(cat "$P/.sdd-state.mig-1.legacy.json")" "backup e' byte-a-byte o v1"
assert_eq "None" "$(field "$P/sdd-state.json" 'd["artifacts"].get("tasks")')" "migrar nao aprova tasks por decreto"
assert_eq "True" "$(field "$P/sdd-state.json" 'd["artifacts"]["techspec"]["approved"]')" "status aprovado preservado"
assert_contains "$(sdd legado migrate-sdd .lt/specs/prd-x --run-id mig-2)" "ja esta em v2" "migrar de novo e' idempotente"
( cd "$W/legado" && python3 "$SDD" migrate-sdd .lt/specs/prd-x --run-id 'x;rm' >/dev/null 2>&1 )
assert_eq "2" "$?" "run_id fora de [A-Za-z0-9._-] e' recusado"

describe "rollback-sdd"
( cd "$W/legado" && python3 "$SDD" rollback-sdd .lt/specs/prd-x --run-id outro >/dev/null 2>&1 )
assert_eq "3" "$?" "run_id que nao criou o estado e' recusado"
sdd legado approve .lt/specs/prd-x tasks >/dev/null
OUT="$(sdd legado rollback-sdd .lt/specs/prd-x --run-id mig-1)"
assert_contains "$OUT" "descartados" "rollback diz o que descarta"
assert_eq "$(cat "$W/v1.before-migrate")" "$(cat "$P/sdd-state.json")" "rollback restaura o v1 exato"
( cd "$W/legado" && python3 "$SDD" rollback-sdd .lt/specs/prd-x >/dev/null 2>&1 )
assert_eq "3" "$?" "sem migracao, nao ha rollback"

describe "orchestrate"
mk_bundle orq
Q="$W/orq/.lt/specs/prd-x"
( cd "$W/orq" && python3 "$SDD" orchestrate .lt/specs/prd-x --run-id r1 >/dev/null 2>&1 )
assert_eq "3" "$?" "sem aprovacao nao orquestra"
for a in prd techspec tasks; do sdd orq approve .lt/specs/prd-x "$a" >/dev/null; done
OUT="$(sdd orq orchestrate .lt/specs/prd-x --run-id r1)"
assert_contains "$OUT" "wave 1: 1.0" "plano de waves registrado"
assert_eq "[['1.0'], ['2.0']]" "$(field "$Q/sdd-state.json" '[r["waves"] for r in d["runs"]][0]')" "waves gravadas no estado"
BEFORE="$(cat "$Q/sdd-state.json")"
assert_contains "$(sdd orq orchestrate .lt/specs/prd-x --run-id r1)" "idempotente" "mesmo run_id devolve o plano gravado"
assert_eq "$BEFORE" "$(cat "$Q/sdd-state.json")" "e nao reescreve o estado"
printf '\n' >> "$Q/tasks.md"
( cd "$W/orq" && python3 "$SDD" orchestrate .lt/specs/prd-x --run-id r2 >/dev/null 2>&1 )
assert_eq "3" "$?" "tasks.md mudado depois da aprovacao bloqueia run novo"
( cd "$W/orq" && python3 "$SDD" orchestrate .lt/specs/prd-x >/dev/null 2>&1 )
assert_eq "2" "$?" "sem --run-id e' uso invalido"

describe "estado v2 corrompido e' recusado"
python3 - "$Q/sdd-state.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d["artifacts"]["prd"]["approved"] = False; json.dump(d, open(p, "w"))
PY
OUT="$( cd "$W/orq" && python3 "$SDD" state .lt/specs/prd-x 2>&1 )"
assert_contains "$OUT" "inconsistentes" "status approved com approved=false nao carrega"

end_describe
