#!/usr/bin/env python3
# orchestrator-ai-harness / scripts / lib / validate-evals-cases.py
#
# Validacao estatica dos casos autorais de eval. Custo zero — nao chama modelo nenhum.
#
# O eval pago responde "a skill melhora o resultado?". Este gate responde as perguntas que nao
# precisam de modelo, e que sao as que quebram em silencio: o caso aponta para uma skill que
# existe? a fixture que ele cita esta em disco? um caso negativo realmente afirma a recusa?
#
# Caso de eval que referencia arquivo inexistente NAO falha ao rodar — ele roda, o agente nao
# acha o arquivo, improvisa, e o grader julga uma resposta sobre nada.
#
# Vive em arquivo proprio porque a primeira versao era um heredoc dentro do gate de shell: o
# gate imprimia as linhas de erro e seguia para o banner de sucesso. Separado, o codigo de
# saida propaga.
#
# Saida: CASOS=, NEGATIVOS=, FIXTURES= e uma linha ERRO= por problema. Sai 1 se houve erro.

import glob
import io
import json
import os
import sys

CHAVES = {"skills", "query", "files", "expected_behavior"}
MIN_COMPORTAMENTOS = 3


def main():
    erros = []
    casos = negativos = fixtures_ok = 0

    for path in sorted(glob.glob("plugins/lt/skills/*/evals/*.json")):
        skill_dir = path.split("/evals/")[0]
        skill = os.path.basename(skill_dir)
        nome = os.path.basename(path)
        rotulo = "%s/%s" % (skill, nome)
        casos += 1

        try:
            data = json.load(io.open(path, encoding="utf-8"))
        except ValueError as exc:
            erros.append("%s: JSON invalido (%s)" % (rotulo, exc))
            continue

        extra = set(data) - CHAVES
        if extra:
            # Chave desconhecida vira caso morto: ninguem a le, e o typo nao aparece.
            erros.append("%s: chave fora do schema: %s" % (rotulo, ", ".join(sorted(extra))))
        faltando = CHAVES - set(data)
        if faltando:
            erros.append("%s: falta %s" % (rotulo, ", ".join(sorted(faltando))))
            continue

        negativo = "-negativo-" in nome
        if negativo:
            negativos += 1

        if not isinstance(data["skills"], list) or not data["skills"]:
            # Tambem no caso negativo: sem declarar a skill, nao ha o que afirmar que NAO deve
            # disparar, e o grader de roteamento gerado ficaria vazio.
            erros.append("%s: 'skills' vazio — o caso nao declara qual skill esta em jogo" % rotulo)
        else:
            for s in data["skills"]:
                if not os.path.isfile(os.path.join("plugins/lt/skills", s, "SKILL.md")):
                    erros.append("%s: declara skill inexistente '%s'" % (rotulo, s))

        if not isinstance(data["query"], str) or not data["query"].strip():
            erros.append("%s: 'query' vazia" % rotulo)

        for f in data["files"]:
            if os.path.exists(os.path.join(skill_dir, f)):
                fixtures_ok += 1
            else:
                erros.append("%s: fixture ausente '%s'" % (rotulo, f))

        comportamentos = data["expected_behavior"]
        if not isinstance(comportamentos, list) or len(comportamentos) < MIN_COMPORTAMENTOS:
            erros.append("%s: 'expected_behavior' com menos de %d itens" % (rotulo, MIN_COMPORTAMENTOS))
        else:
            for b in comportamentos:
                if not isinstance(b, str) or not b.strip():
                    erros.append("%s: comportamento esperado vazio" % rotulo)
            if negativo and not any(
                b.strip().lower().startswith(("nao ", "não ")) for b in comportamentos
            ):
                erros.append(
                    "%s: caso negativo sem nenhum comportamento comecando por 'Nao' — "
                    "o caso nao afirma a recusa, entao nao testa a recusa" % rotulo
                )

    # Skill com linter precisa de ao menos um caso que o exercite; senao o linter nunca e'
    # coberto por eval nenhum.
    for skill_dir in sorted(glob.glob("plugins/lt/skills/*")):
        skill = os.path.basename(skill_dir)
        scripts = glob.glob(os.path.join(skill_dir, "scripts", "*.py"))
        evals = glob.glob(os.path.join(skill_dir, "evals", "*.json"))
        if not scripts or not evals:
            continue
        nomes = [os.path.basename(s) for s in scripts]
        texto = " ".join(io.open(e, encoding="utf-8").read() for e in evals)
        if not any(n in texto for n in nomes):
            erros.append(
                "%s: tem linter (%s) e nenhum caso o menciona" % (skill, ", ".join(nomes))
            )

    print("CASOS=%d" % casos)
    print("NEGATIVOS=%d" % negativos)
    print("FIXTURES=%d" % fixtures_ok)
    for e in erros:
        print("ERRO=%s" % e)
    return 1 if erros else 0


if __name__ == "__main__":
    sys.exit(main())
