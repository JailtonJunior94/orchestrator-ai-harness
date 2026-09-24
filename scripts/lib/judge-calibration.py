#!/usr/bin/env python3
"""Calibracao do juiz LLM do `claude plugin eval` contra rotulos humanos.

POR QUE EXISTE
A eval so' pode virar gate de release se a regua for confiavel. Medido na 0.1.2: o juiz haiku do
host acertou 14 de 20 respostas reais rotuladas a mao — todos os erros foram falsos negativos
(resposta correta reprovada). Gate com juiz de 70% bloqueia release por erro do juiz.

COMO MEDE O JUIZ DO PROPRIO HOST
Um juiz local (outro prompt, outra chamada) nao mede o que o host faz; a divergencia entre os dois
foi observada. Aqui cada item vira um caso em que o agente so' REPETE uma resposta fixa e o grader
llm do host decide — exatamente o caminho que pontua as evals reais.

Uso:
  judge-calibration.py build                  gera plugins/lt/evals-calibration/ a partir de
                                              tests/fixtures/judge-calibration.json
  judge-calibration.py score <report.json> [--min 0.9]
                                              acuracia, falso negativo e falso positivo; exit 1
                                              abaixo do minimo
"""
import json
import os
import shutil
import sys

REPO = os.path.realpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
DATA = os.path.join(REPO, "tests", "fixtures", "judge-calibration.json")
OUT = os.path.join(REPO, "plugins", "lt", "evals-calibration")
FENCE_OPEN = "<<<RESPOSTA"
FENCE_CLOSE = "RESPOSTA>>>"

# O texto do grader e' o MESMO template de scripts/lib/evals-from-json.py: calibrar outro texto
# mediria outro juiz.
GRADER = """---
type: llm
focus: last_message
---

Critério a verificar na resposta final do agente:

> {criterion}

Contexto, só para interpretar o critério (o juiz não recebe o pedido de outra forma): a pessoa usuária pediu "{request}". O agente roda numa sandbox somente leitura: pode ler arquivos e invocar skills, mas não tem shell nem permissão de escrita. Comandos só podem ser indicados, nunca executados.

Julgue apenas este critério — não a qualidade geral da resposta nem se o pedido foi concluído. Indicar o comando ou o plano conta como cumprir, porque a sandbox não permite executar. Um critério negativo ("Não ...") é cumprido quando a resposta não faz o que ele proíbe; ausência basta.
"""


def build():
    data = json.load(open(DATA, encoding="utf-8"))
    if os.path.isdir(OUT):
        shutil.rmtree(OUT)
    for item in data["items"]:
        case = os.path.join(OUT, item["id"])
        os.makedirs(os.path.join(case, "graders"))
        with open(os.path.join(case, "case.yaml"), "w", encoding="utf-8") as stream:
            stream.write('schema_version: "1.1"\nname: "%s"\ndescription: "calibracao do juiz"\n'
                         'tags:\n  - "expect-%s"\nexecution:\n  max_turns: 1\n  allowed_tools: []\n'
                         % (item["id"], item["expected"]))
        with open(os.path.join(case, "prompt.md"), "w", encoding="utf-8") as stream:
            stream.write("Responda reproduzindo EXATAMENTE o texto entre as marcas %s e %s, sem as "
                         "marcas, sem comentar e sem acrescentar nada antes ou depois.\n\n%s\n%s\n%s\n"
                         % (FENCE_OPEN, FENCE_CLOSE, FENCE_OPEN, item["answer"], FENCE_CLOSE))
        with open(os.path.join(case, "graders", "01-criterio.md"), "w", encoding="utf-8") as stream:
            stream.write(GRADER.format(criterion=item["criterion"],
                                       request=item["request"].replace('"', "'")))
    print("calibracao: %d casos em %s" % (len(data["items"]), os.path.relpath(OUT, REPO)))
    return 0


def score(report_path, minimum):
    data = {item["id"]: item for item in json.load(open(DATA, encoding="utf-8"))["items"]}
    report = json.load(open(report_path, encoding="utf-8"))
    right = total = false_neg = false_pos = echo_bad = 0
    misses = []
    for case in report.get("cases", []):
        item = data.get(case["name"])
        if not item:
            continue
        for run in case.get("arms", {}).get("with", []) or case.get("arms", {}).get("none", []) or []:
            graders = [g for g in run.get("graders", []) if g.get("name", "").startswith("01")]
            if run.get("error") or not graders:
                echo_bad += 1
                continue
            verdict = "pass" if graders[0].get("passed") else "fail"
            total += 1
            if verdict == item["expected"]:
                right += 1
            elif item["expected"] == "pass":
                false_neg += 1
                misses.append("%s: juiz FAIL, rotulo PASS" % item["id"])
            else:
                false_pos += 1
                misses.append("%s: juiz PASS, rotulo FAIL" % item["id"])
    if not total:
        print("calibracao: nenhum veredito lido do relatorio", file=sys.stderr)
        return 1
    accuracy = right / float(total)
    print("juiz: acuracia %.3f (%d/%d) · falso negativo %d · falso positivo %d · execucoes invalidas %d"
          % (accuracy, right, total, false_neg, false_pos, echo_bad))
    for miss in misses:
        print("  - " + miss)
    if accuracy < minimum:
        print("JUIZ REPROVADO: acuracia %.3f abaixo do minimo %.2f" % (accuracy, minimum))
        return 1
    print("JUIZ CALIBRADO")
    return 0


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == "build":
        return build()
    if len(sys.argv) >= 3 and sys.argv[1] == "score":
        minimum = float(sys.argv[sys.argv.index("--min") + 1]) if "--min" in sys.argv else 0.9
        return score(sys.argv[2], minimum)
    sys.stderr.write(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
