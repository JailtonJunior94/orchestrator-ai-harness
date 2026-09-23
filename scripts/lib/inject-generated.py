#!/usr/bin/env python3
# orchestrator-ai-harness / scripts / lib / inject-generated.py
#
# Substitui o bloco entre <!-- BEGIN GENERATED: <id> --> e <!-- END GENERATED: <id> --> pela
# saida de um gerador. Com --check, nao escreve e sai 1 se divergir.
#
# Existe para que prosa gerada nao envelheca em silencio — o defeito que a propria secao de
# drift denuncia seria cometido por ela mesma se fosse escrita a mao.

import argparse
import io
import re
import subprocess
import sys


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", required=True)
    ap.add_argument("--id", required=True)
    ap.add_argument("--generator", required=True)
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()

    proc = subprocess.run(["bash", a.generator], stdout=subprocess.PIPE)
    if proc.returncode != 0:
        sys.stderr.write("gerador falhou: %s\n" % a.generator)
        return 1
    novo = proc.stdout.decode("utf-8")

    texto = io.open(a.file, encoding="utf-8").read()
    padrao = re.compile(
        r"<!-- BEGIN GENERATED: %s.*?-->.*?<!-- END GENERATED: %s -->" % (re.escape(a.id), re.escape(a.id)),
        re.DOTALL,
    )
    if not padrao.search(texto):
        sys.stderr.write("marcadores '%s' nao encontrados em %s\n" % (a.id, a.file))
        return 1

    atualizado = padrao.sub(lambda _: novo.rstrip(), texto)

    if a.check:
        # A data muda todo dia; compara-la faria o gate falhar sozinho. O que importa e' o
        # conteudo — os numeros que a secao afirma.
        def sem_data(s):
            return re.sub(r"_Gerado em \d{4}-\d{2}-\d{2}[^\n]*_", "", s)
        if sem_data(atualizado) != sem_data(texto):
            sys.stderr.write(
                "bloco '%s' em %s esta desatualizado.\n"
                "  Rode: python3 scripts/lib/inject-generated.py --file %s --id %s --generator %s\n"
                % (a.id, a.file, a.file, a.id, a.generator)
            )
            return 1
        print("bloco '%s' em dia" % a.id)
        return 0

    io.open(a.file, "w", encoding="utf-8").write(atualizado)
    print("bloco '%s' atualizado em %s" % (a.id, a.file))
    return 0


if __name__ == "__main__":
    sys.exit(main())
