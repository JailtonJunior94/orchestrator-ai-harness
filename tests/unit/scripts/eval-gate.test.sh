#!/usr/bin/env bash
# tests / unit / scripts / eval-gate.test.sh
#
# O gate transforma a eval em bloqueio de release. Cada limite tem um caso que o viola sozinho,
# para provar que o gate reprova pelo motivo certo — e um relatorio limpo que ele aprova.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
. "$REPO/tests/unit/lib/assert.sh"

W="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$W"' EXIT
# Copia minima do repo: o gate le docs/benchmarks e plugins/lt relativos a si mesmo.
mkdir -p "$W/r/scripts/lib" "$W/r/docs/benchmarks" "$W/r/plugins/lt/skills/x"
cp "$REPO/scripts/lib/eval-gate.py" "$W/r/scripts/lib/"
printf -- '---\nname: x\ndescription: y\n---\n' > "$W/r/plugins/lt/skills/x/SKILL.md"
printf '{"judges":{"sonnet":{"accuracy":0.93},"haiku":{"accuracy":0.73}}}\n' > "$W/r/docs/benchmarks/judge-calibration.json"
GATE="$W/r/scripts/lib/eval-gate.py"

mk() {  # $1=arquivo $2=juiz $3=runs $4=score_com $5=score_sem $6=roteamento_positivo(true|false) $7=negativo_calado(true|false)
  python3 - "$@" <<'PY'
import json, sys
out, judge, runs, w, wo, pos, neg = sys.argv[1], sys.argv[2], int(sys.argv[3]), float(sys.argv[4]), float(sys.argv[5]), sys.argv[6] == "true", sys.argv[7] == "true"
def run(score, fired):
    return {"score": score, "graders": [{"name": "00-roteamento-x", "passed": fired}]}
cases = [
    {"name": "x--01-positivo", "arms": {"with": [run(w, pos) for _ in range(runs)], "without": [run(wo, False) for _ in range(runs)]}},
    {"name": "x--02-negativo-algo", "arms": {"with": [run(w, neg) for _ in range(runs)], "without": [run(wo, True) for _ in range(runs)]}},
]
json.dump({"suite": {"judgeModel": judge}, "partial": False, "cases": cases, "costUsd": 1,
           "aggregates": {"overallScore": w, "overallPassRate": 0.5, "meanDelta": w - wo}}, open(out, "w"))
PY
}
gate() { python3 "$GATE" "$@" 2>&1; }

describe "eval-gate check"
mk "$W/ok.json" sonnet 3 0.8 0.6 true true
assert_contains "$(gate check "$W/ok.json")" "EVAL GATE APROVADO" "relatorio limpo passa"
mk "$W/j.json" haiku 3 0.8 0.6 true true
assert_contains "$(gate check "$W/j.json")" "acuracia 0.73" "juiz nao calibrado reprova"
mk "$W/r.json" sonnet 2 0.8 0.6 true true
assert_contains "$(gate check "$W/r.json")" "minimo e' 3" "menos de 3 execucoes reprova"
mk "$W/p.json" sonnet 3 0.8 0.6 false true
assert_contains "$(gate check "$W/p.json")" "roteamento positivo" "skill que nao dispara reprova"
mk "$W/n.json" sonnet 3 0.8 0.6 true false
assert_contains "$(gate check "$W/n.json")" "roteamento negativo" "skill que dispara onde nao devia reprova"
mk "$W/d.json" sonnet 3 0.5 0.7 true true
assert_contains "$(gate check "$W/d.json")" "piora o modelo" "skill abaixo do modelo sem plugin reprova"

describe "linha de base e frescor"
assert_contains "$(gate fresh)" "ausente" "sem linha de base o release bloqueia"
gate check "$W/ok.json" --write >/dev/null
assert_contains "$(gate fresh)" "EVAL EM DIA" "linha de base aprovada sobre o conteudo atual libera"
mk "$W/reg.json" sonnet 3 0.7 0.6 true true
assert_contains "$(gate check "$W/reg.json")" "regrediu" "queda maior que a tolerancia contra a linha de base reprova"
printf 'mudou\n' >> "$W/r/plugins/lt/skills/x/SKILL.md"
assert_contains "$(gate fresh)" "EVAL DESATUALIZADA" "skill editada depois da eval bloqueia o release"
end_describe
