#!/usr/bin/env python3
# orchestrator-ai-harness / scripts / lib / check-plugin-counts.py
#
# Conta skills, commands, agents e hooks EM DISCO e confere toda contagem escrita em prosa
# ("Onze hooks", "12 skills") contra esse numero.
#
# POR QUE EXISTE
# Contagem em prosa sem teste que a cruze com `ls` envelhece em silencio: uma skill entra, o
# README continua dizendo o numero antigo, e prosa que mente e' pior que prosa ausente. O
# harness de referencia acumulou badge, README de plugin e arvore de CONTRIBUTING com numeros
# errados ao mesmo tempo — cada um conferido "a olho" por alguem diferente.
#
# AS DUAS FORMAS DE AFIRMACAO
# 1. Total ("Onze hooks", "21 skills", "4 commands"): comparado com o disco.
# 2. Lista ("Onze skills: `a → b → c`, mais `d`"): comparada com o numero de nomes em backtick
#    que a propria frase enumera, ate' o fim do paragrafo. Uma contagem de subconjunto nao pode
#    ser conferida contra o total, mas pode ser conferida contra a lista que ela afirma contar.
#
# ATRIBUICAO CONSERVADORA: "um"/"uma" nao contam (sao artigo), e bloco de codigo cercado por ```
# e' ignorado (exemplo nao e' afirmacao). Na duvida, nao confere — falso positivo ensina a
# desligar o gate.
#
# LISTA FIXA DE ARQUIVOS (PROSE_FILES), nao descoberta: arquivo novo de prosa entra aqui no mesmo
# PR. Faltar um arquivo da lista e' FALHA — a lista e' o inventario do que se promete conferir.
# As `description` do plugin.json e do marketplace.json entram como texto virtual.
#
# Uso:
#   python3 scripts/lib/check-plugin-counts.py --root <repo> [arquivo.md ...]
#   python3 scripts/lib/check-plugin-counts.py --root <repo> --disk     # so imprime o disco (JSON)
# Exit: 0 tudo confere · 1 alguma contagem diverge ou arquivo da lista ausente · 2 uso invalido
#
# scripts/validate-playbook-counts.sh e' a porta de entrada em shell e delega para ca.

import argparse
import glob
import json
import os
import re
import sys

PROSE_FILES = (
    "README.md",
    "CLAUDE.md",
    "CONTRIBUTING.md",
    "PILOT-SETUP.md",
    "SECURITY.md",
    "docs/REPLICATION-GUIDE.md",
    "docs/INDEX.md",
    "docs/VERSIONING.md",
    "docs/RELEASE-CHECKLIST.md",
    "docs/PLUGIN-DEVELOPMENT.md",
    "docs/command-glossary.md",
    "docs/language-policy.md",
    "docs/enterprise-rollout.md",
    "enterprise/README.md",
    "plugins/lt/README.md",
)

WORDS = {
    "dois": 2, "duas": 2, "três": 3, "tres": 3, "quatro": 4, "cinco": 5, "seis": 6,
    "sete": 7, "oito": 8, "nove": 9, "dez": 10, "onze": 11, "doze": 12, "treze": 13,
    "catorze": 14, "quatorze": 14, "quinze": 15, "dezesseis": 16, "dezessete": 17,
    "dezoito": 18, "dezenove": 19, "vinte": 20,
}
NOUN = {"hooks": "hook", "skills": "skill", "commands": "command", "comandos": "command",
        "agents": "agent", "agentes": "agent"}
CLAIM = re.compile(
    r"\b(\d+|%s)\s+(%s)\b" % ("|".join(sorted(WORDS, key=len, reverse=True)), "|".join(NOUN)),
    re.IGNORECASE,
)


def disk_counts(root):
    plugin = os.path.join(root, "plugins", "lt")
    hooks_json = json.load(open(os.path.join(plugin, "hooks", "hooks.json"), encoding="utf-8"))["hooks"]
    return {
        # "hooks" e' o numero REGISTRADO no hooks.json: e' o que roda. O smoke cruza esse numero
        # com os scripts em disco; aqui a prosa e' cruzada com o que o host executa.
        "hook": sum(len(m["hooks"]) for v in hooks_json.values() for m in v),
        "skill": len(glob.glob(os.path.join(plugin, "skills", "*", "SKILL.md"))),
        "command": len(glob.glob(os.path.join(plugin, "commands", "*.md"))),
        "agent": len(glob.glob(os.path.join(plugin, "agents", "*.md"))),
    }


def check_text(label, text, disk):
    """Devolve (erros, afirmacoes_verificadas) para um texto."""
    errors = 0
    checked = 0
    in_fence = False
    offset = 0
    for line in text.split("\n"):
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
        if not in_fence:
            for m in CLAIM.finditer(line):
                raw, noun = m.group(1).lower(), NOUN[m.group(2).lower()]
                claimed = int(raw) if raw.isdigit() else WORDS[raw]
                start = offset + m.start()
                paragraph = text[start:].split("\n\n", 1)[0]
                lineno = text.count("\n", 0, start) + 1
                checked += 1
                if paragraph[m.end() - m.start():].lstrip().startswith(":"):
                    # Um trecho entre crases pode listar varios nomes (`a → b → c`): conta cada
                    # nome kebab dentro dele, nao o trecho.
                    listed = sum(len(re.findall(r"[a-z][a-z0-9]*(?:-[a-z0-9]+)*", span))
                                 for span in re.findall(r"`([^`]+)`", paragraph))
                    if listed != claimed:
                        print("FALHA: %s:%d afirma %d %ss e enumera %d" % (label, lineno, claimed, noun, listed))
                        errors += 1
                elif claimed != disk[noun]:
                    print("FALHA: %s:%d afirma %d %ss; o disco tem %d" % (label, lineno, claimed, noun, disk[noun]))
                    errors += 1
        offset += len(line) + 1
    return errors, checked


def main():
    parser = argparse.ArgumentParser(description="Confere contagens em prosa contra o disco.")
    parser.add_argument("--root", required=True)
    parser.add_argument("--disk", action="store_true", help="imprime as contagens do disco e sai")
    parser.add_argument("files", nargs="*")
    args = parser.parse_args()

    root = os.path.realpath(args.root)
    disk = disk_counts(root)
    if args.disk:
        print(json.dumps(disk, sort_keys=True))
        return 0

    default_mode = not args.files
    files = list(args.files) if args.files else list(PROSE_FILES)

    errors = 0
    checked = 0
    for rel in files:
        path = rel if os.path.isabs(rel) else os.path.join(root, rel)
        if not os.path.isfile(path):
            print("FALHA: %s nao existe" % rel)
            errors += 1
            continue
        e, c = check_text(rel, open(path, encoding="utf-8").read(), disk)
        errors += e
        checked += c

    if default_mode:
        # As `description` de manifesto sao prosa publicada: aparecem no `plugin details` e na
        # listagem do marketplace. Contagem ali mente para quem instala, antes de qualquer doc.
        for rel in (".claude-plugin/marketplace.json", "plugins/lt/.claude-plugin/plugin.json"):
            path = os.path.join(root, rel)
            if not os.path.isfile(path):
                continue
            data = json.load(open(path, encoding="utf-8"))
            texts = [data.get("description") or ""]
            texts += [p.get("description") or "" for p in data.get("plugins", [])]
            for text in texts:
                e, c = check_text(rel + "#description", text, disk)
                errors += e
                checked += c

    if errors:
        return 1
    print("contagens em prosa conferem com o disco (%d afirmacao(oes) verificada(s))" % checked)
    return 0


if __name__ == "__main__":
    sys.exit(main())
