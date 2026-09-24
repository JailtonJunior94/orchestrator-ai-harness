#!/usr/bin/env bash
# orchestrator-ai-harness / scripts / check-eval-routing.sh
#
# Le o --json de um run de `claude plugin eval` e responde a UMA pergunta: a skill disparou quando
# deveria, e ficou calada quando nao deveria?
#
# NAO FALHA POR NOTA. Nota baixa e' informacao sobre qualidade da resposta; roteamento quebrado
# e' a skill deixando de existir na pratica. Sao coisas diferentes, e misturar as duas faz o
# time ignorar as duas.
#
# Delta negativo tambem NAO falha: pode ser variacao do modelo, do caso, ou do dia.
#
# FORMATO LIDO (relatorio `schemaVersion: 1` do CLI 2.1.x): `cases[].graders[]` traz a definicao
# (tipo e config) e `cases[].arms.with[].graders[]` traz o veredito por run. O grader de
# roteamento e' o `tool_used` na ferramenta `Skill` que o gerador (scripts/lib/evals-from-json.py)
# nomeia `00-roteamento-<skill>`: `max: 0` marca caso negativo (a skill NAO deve disparar), o
# resto e' positivo. So' o braco `with` conta — sob `--ablation with-without` o braco sem plugin
# nem recebe o grader, porque sem o plugin a skill nao existe.
#
# A primeira versao varria o JSON atras de qualquer no com "roteamento" no nome e lia `passed`
# de cada um: contava a DEFINICAO do grader (que nao tem `passed`) como reprovada e nunca separava
# positivo de negativo. Por isso agora a leitura e' pelo formato, e formato desconhecido falha
# alto em vez de virar verde.
#
# SAIDA: por caso, quantos runs acertaram o roteamento; no fim, precisao de disparo (positivos
# que dispararam) e de silencio (negativos que ficaram calados). Sai 1 quando algum caso errou o
# roteamento na maioria dos runs; caso que errou em alguns runs mas nao na maioria e' INSTAVEL e
# so' avisa. Run que morreu antes de avaliar (erro do host) nao conta como acerto nem como erro,
# e aparece na contagem.

set -uo pipefail
REPORT="${1:-eval-out/report.json}"

if [ ! -r "$REPORT" ]; then
  printf '[lt] relatorio de eval ausente: %s\n' "$REPORT" >&2
  printf '     Sem ele nao da para afirmar nada sobre roteamento — e nao afirmar e melhor que afirmar errado.\n' >&2
  exit 1
fi
command -v python3 >/dev/null 2>&1 || { printf 'python3 obrigatorio\n' >&2; exit 2; }

python3 - "$REPORT" <<'PYEOF'
import json, sys

try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
except (IOError, OSError, ValueError) as exc:
    sys.stderr.write("[lt] relatorio ilegivel: %s\n" % exc)
    raise SystemExit(1)

if not isinstance(data, dict) or not isinstance(data.get("cases"), list):
    sys.stderr.write(
        "[lt] formato de relatorio desconhecido (sem 'cases'). Isso nao e' 'tudo certo': o CLI\n"
        "     mudou o schema do --json e este leitor precisa acompanhar.\n")
    raise SystemExit(1)


def routing_defs(case):
    out = {}
    for g in case.get("graders") or []:
        cfg = g.get("config") or {}
        if g.get("type") == "tool_used" and cfg.get("tool") == "Skill" \
                and str(g.get("name", "")).startswith("00-roteamento-"):
            out[g["name"]] = cfg.get("max") == 0
    return out


linhas = []
quebrados = []
instaveis = []
tot = {True: [0, 0], False: [0, 0]}   # negativo? -> [acertos, runs avaliados]
sem_avaliacao = 0
casos_com_roteamento = 0

for case in data["cases"]:
    defs = routing_defs(case)
    if not defs:
        continue
    casos_com_roteamento += 1
    runs = (case.get("arms") or {}).get("with") or []
    for gname, negativo in sorted(defs.items()):
        ok = aval = 0
        for run in runs:
            if not run:
                sem_avaliacao += 1
                continue
            vered = [g for g in run.get("graders") or [] if g.get("name") == gname]
            if not vered:
                sem_avaliacao += 1
                continue
            aval += 1
            ok += 1 if vered[0].get("passed") else 0
        tot[negativo][0] += ok
        tot[negativo][1] += aval
        rotulo = "negativo" if negativo else "positivo"
        estado = "ok"
        if aval and ok * 2 < aval:
            estado = "QUEBRADO"
            quebrados.append(case["name"])
        elif aval and ok < aval:
            estado = "instavel"
            instaveis.append(case["name"])
        elif not aval:
            estado = "sem runs avaliados"
        linhas.append("  %-62s %-8s %d/%d  %s" % (case["name"], rotulo, ok, aval, estado))

if not casos_com_roteamento:
    sys.stderr.write(
        "[lt] nenhum grader de roteamento encontrado no relatorio.\n"
        "     Isso nao e' 'tudo certo': ou o formato mudou, ou os casos perderam o grader.\n")
    raise SystemExit(1)

print("roteamento por caso (runs corretos / runs avaliados, braco com plugin):")
for l in linhas:
    print(l)


def pct(a, b):
    return "%d/%d (%.0f%%)" % (a, b, 100.0 * a / b) if b else "0/0 (sem dados)"


print("")
print("positivos que dispararam:        %s" % pct(*tot[False]))
print("negativos que ficaram calados:   %s" % pct(*tot[True]))
if sem_avaliacao:
    print("runs sem avaliacao (erro do host ou teto de custo): %d" % sem_avaliacao)
if data.get("partial"):
    print("relatorio PARCIAL: %s" % data.get("partialReason"))

if instaveis:
    print("")
    print("instaveis (erraram em parte dos runs): %s" % ", ".join(instaveis))

if quebrados:
    sys.stderr.write("\n[lt] ROTEAMENTO QUEBRADO em %d caso(s):\n" % len(quebrados))
    for q in quebrados:
        sys.stderr.write("  - %s\n" % q)
    sys.stderr.write("\n  A skill deixou de disparar quando deveria (ou disparou quando nao deveria)\n"
                     "  na maioria dos runs.\n")
    raise SystemExit(1)

print("")
print("roteamento intacto: nenhum caso errou o roteamento na maioria dos runs")
PYEOF
