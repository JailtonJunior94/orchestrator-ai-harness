#!/usr/bin/env bash
# tests / unit / scripts / eval-routing.test.sh
#
# Dois contratos do eval pago que quebram em silencio e custam dinheiro para descobrir:
#
# 1. O gerador (scripts/lib/evals-from-json.py) emite o grader de roteamento negativo com
#    `min: 0` + `max: 0`. So' `max: 0` vira a faixa `1..0` no host (min tem default 1): o
#    negativo reprova ate' quando a skill fica calada. E nao usa `context.add_dirs`, que o host
#    resolve relativo ao diretorio do caso e nunca anuncia ao agente.
# 2. check-eval-routing.sh le o formato real do --json (definicao em `cases[].graders`, veredito
#    em `cases[].arms.with[].graders`), separa positivo de negativo e falha alto em formato
#    desconhecido. Relatorio sintetico aqui: o real so' existe depois de um run pago.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
. "$REPO/tests/unit/lib/assert.sh"

CHK="$REPO/scripts/check-eval-routing.sh"
W="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$W"' EXIT

describe "gerador de casos de eval"

gen_rc() { (cd "$REPO" && python3 scripts/lib/evals-from-json.py --check >/dev/null 2>&1); }
assert_exit_code 0 gen_rc

NEG_SEM_MIN=""
for g in "$REPO"/plugins/lt/evals/*negativo*/graders/00-roteamento-*.md; do
  [ -f "$g" ] || continue
  if ! grep -q '^min: 0$' "$g" || ! grep -q '^max: 0$' "$g"; then
    NEG_SEM_MIN="$NEG_SEM_MIN ${g#"$REPO/"}"
  fi
done
assert_eq "" "$NEG_SEM_MIN" "todo roteamento negativo declara min: 0 e max: 0"

ADD_DIRS="$(grep -l 'add_dirs' "$REPO"/plugins/lt/evals/*/case.yaml 2>/dev/null || true)"
assert_eq "" "$ADD_DIRS" "nenhum caso depende de context.add_dirs"

LLM_SEM_PEDIDO=""
for g in "$REPO"/plugins/lt/evals/*/graders/0[1-9]-*.md; do
  [ -f "$g" ] || continue
  grep -q '^type: llm$' "$g" || continue
  grep -q 'a pessoa usuária pediu' "$g" || LLM_SEM_PEDIDO="$LLM_SEM_PEDIDO ${g#"$REPO/"}"
done
assert_eq "" "$LLM_SEM_PEDIDO" "todo criterio llm leva o pedido original (o juiz nao o recebe)"

describe "check-eval-routing.sh"

# report <pos_passou> <neg_passou> <ok|legacy>: um caso positivo e um negativo, dois runs cada.
report() {
  python3 - "$W/r.json" "$1" "$2" "$3" <<'PY'
import json, sys
out, p1, n1, fmt = sys.argv[1], sys.argv[2] == "1", sys.argv[3] == "1", sys.argv[4]
def case(name, neg, passed):
    cfg = {"tool": "Skill", "input_match": "x", "min": 0 if neg else 1}
    if neg:
        cfg["max"] = 0
    g = "00-roteamento-review"
    run = {"score": 1, "graders": [{"name": g, "passed": passed, "withOnly": True, "scored": False}]}
    return {"name": name, "graders": [{"name": g, "type": "tool_used", "weight": 1, "config": cfg}],
            "arms": {"with": [run, dict(run, graders=[dict(run["graders"][0], passed=True)])],
                     "without": [{"score": 1, "graders": []}]}}
data = {"schemaVersion": 1, "partial": False,
        "cases": [case("review--01-x", False, p1), case("review--04-negativo-y", True, n1)]}
if fmt == "legacy":
    data = {"results": data["cases"]}
json.dump(data, open(out, "w"))
PY
}
chk_rc() { bash "$CHK" "$W/r.json" >/dev/null 2>&1; }
chk() { bash "$CHK" "$W/r.json" 2>&1; }

report 1 1 ok
assert_exit_code 0 chk_rc
assert_contains "$(chk)" "positivos que dispararam:        2/2" "conta positivos no braco com plugin"
assert_contains "$(chk)" "negativos que ficaram calados:   2/2" "conta negativos separado dos positivos"

report 0 1 ok
assert_exit_code 0 chk_rc
assert_contains "$(chk)" "instavel" "erro em metade dos runs e' instavel, nao quebrado"

python3 - "$W/r.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for c in d["cases"]:
    if "negativo" in c["name"]:
        for r in c["arms"]["with"]:
            r["graders"][0]["passed"] = False
json.dump(d, open(sys.argv[1], "w"))
PY
assert_exit_code 1 chk_rc
assert_contains "$(chk)" "ROTEAMENTO QUEBRADO" "negativo que disparou em todos os runs reprova"

report 1 1 legacy
assert_exit_code 1 chk_rc
assert_contains "$(chk)" "formato de relatorio desconhecido" "formato desconhecido falha alto"

missing_rc() { bash "$CHK" "$W/nao-existe.json" >/dev/null 2>&1; }
assert_exit_code 1 missing_rc

end_describe
