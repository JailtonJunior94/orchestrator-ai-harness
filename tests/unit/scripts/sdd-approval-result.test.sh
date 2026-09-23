#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
. "$REPO/tests/unit/lib/assert.sh"

SDD="$REPO/plugins/lt/lib/sdd.py"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
git -C "$W" init -q
P="$W/.lt/specs/prd-x"
mkdir -p "$P"
printf '# PRD\nRF-01 teste\n' > "$P/prd.md"
printf '<!-- spec-hash-prd: %064d -->\n# TechSpec\n' 0 > "$P/techspec.md"
printf '<!-- spec-hash-prd: %064d -->\n<!-- spec-hash-techspec: %064d -->\n# Tasks\n| # | Tarefa | Status | Dependencias | Paralelizavel | Skills |\n|---|---|---|---|---|---|\n| 1.0 | Fazer | pending | — | — | — |\n## Cobertura de Requisitos\nRF-01\n' 0 0 > "$P/tasks.md"

describe "aprovacao por hash e schema de resultado"
( cd "$W" && python3 "$SDD" sync-spec-hash "$P" >/dev/null )
( cd "$W" && python3 "$SDD" approve "$P" prd >/dev/null )
( cd "$W" && python3 "$SDD" approve "$P" techspec >/dev/null )
( cd "$W" && python3 "$SDD" approve "$P" tasks >/dev/null )
( cd "$W" && python3 "$SDD" assert-approved "$P" tasks >/dev/null )
assert_eq "0" "$?" "cadeia aprovada e inalterada passa"

printf '\nmutacao\n' >> "$P/tasks.md"
( cd "$W" && python3 "$SDD" assert-approved "$P" tasks >/dev/null 2>&1 )
assert_eq "3" "$?" "tasks alterada depois da aprovacao bloqueia"

RESULT="$W/result.json"
cat > "$RESULT" <<'JSON'
{"schema_version":2,"run_id":"run-1","task_id":"1.0","attempt":1,"status":"done","base_sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","patch_sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","patch_ref":"task.patch","final_state_sha256":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","coverage_regression":false,"tests":[{"command":"test","exit_code":0,"output_sha256":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"}],"criteria":[{"id":"RF-01","evidence_ref":"test.log"}],"evidence":["test.log"],"review_verdict":"APPROVED"}
JSON
python3 "$SDD" validate-result execution "$RESULT" --task-id 1.0 >/dev/null
assert_eq "0" "$?" "execution-result v2 valido passa"

python3 - "$RESULT" <<'PY'
import json, sys
p=sys.argv[1]; d=json.load(open(p)); d["extra"]="nao"; json.dump(d,open(p,"w"))
PY
python3 "$SDD" validate-result execution "$RESULT" >/dev/null 2>&1
assert_eq "1" "$?" "campo desconhecido falha"

CAP="$(python3 "$SDD" runtime-capabilities --host opencode)"
assert_contains "$CAP" '"host": "opencode"' "capacidade identifica o host"
assert_contains "$CAP" '"safe_concurrent_writes": false' "concorrencia degrada de forma explicita"
end_describe
