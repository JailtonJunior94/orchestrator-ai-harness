#!/usr/bin/env python3
# orchestrator-ai-harness / scripts / lib / evals-from-json.py
#
# Converte os casos de eval no formato AUTORAL do time para o formato OFICIAL que
# `claude plugin eval` consome.
#
# POR QUE CONVERTER EM VEZ DE MIGRAR
# O time ja escreveu 26 casos no formato {skills, query, files, expected_behavior}, com casos
# negativos — que e' exatamente o que a orientacao oficial recomenda testar. Esse formato e'
# facil de escrever a mao e e' onde o conhecimento esta. O formato do host e' mais verboso e
# existe para ser executado, nao para ser escrito. Converter preserva a fonte autoral e da' ao
# host o que ele precisa.
#
# O QUE CADA CAMPO VIRA
#   skills[]            -> grader de ROTEAMENTO (`type: tool_used`, `tool: Skill`)
#   query               -> prompt.md do caso
#   files[]             -> context.add_dirs, para a fixture existir na sandbox
#   expected_behavior[] -> um grader `llm` por item, com o texto LITERAL como criterio
#
# CASO NEGATIVO (arquivo `NN-negativo-*.json`): a expectativa se inverte — a skill NAO deve
# disparar. Vira `max: 0` no grader de roteamento. A orientacao oficial e' explicita sobre
# testar tambem os casos em que a skill nao deve ser invocada.
#
# `--check` nao escreve nada e sai 1 se o que esta em disco divergir do que seria gerado. E' o
# que o CI roda: artefato gerado e commitado que envelhece em silencio e' pior que artefato
# ausente.

import argparse
import glob
import io
import json
import os
import re
import sys

SKILLS_DIR = "plugins/lt/skills"
OUT_DIR = "plugins/lt/evals"


def slug(text):
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def is_negative(path):
    return bool(re.search(r"\d+-negativo-", os.path.basename(path)))


def build_case(skill, case_path, data):
    name = "%s--%s" % (skill, slug(os.path.basename(case_path)[:-5]))
    negative = is_negative(case_path)

    case = {
        "schema_version": "1.1",
        "name": name,
        "description": data.get("query", "")[:200],
        "tags": ["negativo"] if negative else ["roteamento"],
        "execution": {
            "max_turns": 8,
            "allowed_tools": ["Read", "Glob", "Grep", "Skill"],
        },
    }

    # Os fixtures citados pelo caso precisam existir na sandbox do run.
    dirs = sorted({os.path.dirname(f) for f in data.get("files", []) if f})
    if dirs:
        case["context"] = {
            "add_dirs": [os.path.join(SKILLS_DIR, skill, d) for d in dirs]
        }

    graders = {}

    # Grader de ROTEAMENTO. Formato oficial: casar a invocacao da ferramenta Skill pelo nome,
    # aceitando a forma com namespace do plugin.
    for declared in data.get("skills", []):
        # Nome de skill e' kebab-case: so o ponto precisaria de escape, e nao ha. re.escape
        # escaparia o hifen tambem (`postgres\-guidelines`), o que e' ruido e depende do motor
        # de regex do host para ser inofensivo.
        pattern = r'"skill"\s*:\s*"(?:[\w-]+:)?%s"' % declared.replace(".", r"\.")
        body = [
            "---",
            "type: tool_used",
            "tool: Skill",
            "input_match: '%s'" % pattern,
        ]
        if negative:
            # A skill NAO deve disparar neste caso.
            body.append("max: 0")
        else:
            body.append("min: 1")
        body += [
            "---",
            "",
            "A skill `%s` %s ser invocada neste cenario." % (
                declared, "NAO deve" if negative else "deve"),
            "",
            "Sob `--ablation with-without`, este grader vira indicador nao pontuado: sem o",
            "plugin carregado ele nunca poderia passar, entao pontua-lo compararia coisas",
            "diferentes.",
            "",
        ]
        graders["00-roteamento-%s.md" % declared] = "\n".join(body)

    # Um grader de conteudo por comportamento esperado, com o texto autoral literal.
    for i, behavior in enumerate(data.get("expected_behavior", []), 1):
        graders["%02d-%s.md" % (i, slug(behavior)[:40])] = "\n".join([
            "---",
            "type: llm",
            "focus: last_message",
            "---",
            "",
            "A resposta satisfaz o seguinte criterio, escrito pelo autor do caso:",
            "",
            "> %s" % behavior,
            "",
        ])

    return name, case, graders, data.get("query", "")


def render(case):
    """YAML minimo, sem dependencia externa — o harness nao pode exigir PyYAML para gerar."""
    lines = []

    def emit(key, value, indent=0):
        pad = "  " * indent
        if isinstance(value, dict):
            lines.append("%s%s:" % (pad, key))
            for k, v in value.items():
                emit(k, v, indent + 1)
        elif isinstance(value, list):
            lines.append("%s%s:" % (pad, key))
            for item in value:
                lines.append("%s  - %s" % (pad, json.dumps(item, ensure_ascii=False)))
        else:
            lines.append("%s%s: %s" % (pad, key, json.dumps(value, ensure_ascii=False)))

    for k, v in case.items():
        emit(k, v)
    return "\n".join(lines) + "\n"


def collect():
    out = {}
    for skill_dir in sorted(glob.glob(os.path.join(SKILLS_DIR, "*", "evals"))):
        skill = skill_dir.split(os.sep)[-2]
        for case_path in sorted(glob.glob(os.path.join(skill_dir, "*.json"))):
            with io.open(case_path, encoding="utf-8") as fh:
                try:
                    data = json.load(fh)
                except ValueError as exc:
                    sys.stderr.write("JSON invalido em %s: %s\n" % (case_path, exc))
                    raise SystemExit(1)
            name, case, graders, prompt = build_case(skill, case_path, data)
            files = {"case.yaml": render(case), "prompt.md": prompt.rstrip() + "\n"}
            for gname, gbody in graders.items():
                files[os.path.join("graders", gname)] = gbody
            out[name] = files
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true",
                        help="nao escreve; sai 1 se o disco divergir do gerado")
    args = parser.parse_args()

    generated = collect()
    diverged = []
    written = 0

    for name, files in generated.items():
        base = os.path.join(OUT_DIR, name)
        for rel, body in files.items():
            path = os.path.join(base, rel)
            current = None
            if os.path.isfile(path):
                with io.open(path, encoding="utf-8") as fh:
                    current = fh.read()
            if current == body:
                continue
            if args.check:
                diverged.append(path)
            else:
                os.makedirs(os.path.dirname(path), exist_ok=True)
                with io.open(path, "w", encoding="utf-8") as fh:
                    fh.write(body)
                written += 1

    # Diretorio gerado que sobreviveu ao caso de origem seria um eval orfao rodando para sempre.
    if os.path.isdir(OUT_DIR):
        for existing in sorted(os.listdir(OUT_DIR)):
            if existing not in generated and os.path.isdir(os.path.join(OUT_DIR, existing)):
                if args.check:
                    diverged.append(os.path.join(OUT_DIR, existing) + " (orfao)")
                else:
                    import shutil
                    shutil.rmtree(os.path.join(OUT_DIR, existing))

    if args.check:
        if diverged:
            sys.stderr.write("evals gerados estao desatualizados (%d):\n" % len(diverged))
            for d in diverged[:10]:
                sys.stderr.write("  %s\n" % d)
            sys.stderr.write("\n  Rode: python3 scripts/lib/evals-from-json.py\n")
            return 1
        print("evals gerados em dia: %d casos" % len(generated))
        return 0

    print("gerados %d casos (%d arquivos escritos) em %s" % (len(generated), written, OUT_DIR))
    return 0


if __name__ == "__main__":
    sys.exit(main())
