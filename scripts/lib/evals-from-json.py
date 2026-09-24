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
#   files[]             -> conteudo da fixture anexado ao prompt.md
#   expected_behavior[] -> um grader `llm` por item, com o texto autoral como criterio
#
# POR QUE A FIXTURE VAI NO PROMPT E NAO EM `context.add_dirs`
# A primeira versao apontava `add_dirs` para `plugins/lt/skills/<s>/evals/fixtures` e todo caso
# com fixture morria antes de rodar com `path ... does not exist`: o host resolve `add_dirs`
# relativo ao DIRETORIO DO CASO e recusa entrada que saia dele. Mesmo com o caminho certo, o
# `add_dirs` so' concede permissao de leitura num caminho absoluto que o agente nao conhece — ele
# nao e' copiado para o cwd da sandbox (que comeca vazio) nem anunciado ao modelo. Medido: o
# agente procurou `evals/fixtures/x.patch` no cwd, nao achou e respondeu BLOCKED por falta do
# diff. As fixtures sao pequenas; embuti-las no prompt faz o caso testar a skill, e nao a
# capacidade de adivinhar um caminho, igual nos dois bracos do `--ablation with-without`.
#
# CASO NEGATIVO (arquivo `NN-negativo-*.json`): a expectativa se inverte — a skill NAO deve
# disparar. Vira `min: 0` + `max: 0` no grader de roteamento. So' `max: 0` nao basta: `min` tem
# default 1 no host, e a faixa `1..0` nunca passa — o negativo reprovava ate' quando a skill
# ficava calada.
#
# O JUIZ NAO VE O PEDIDO
# O grader `llm` do host manda ao juiz apenas o criterio e a ultima mensagem do agente. Criterio
# como "Nao cria PRD para uma correcao visual pontual" e' injulgavel sem saber que o pedido era
# um botao desalinhado — o juiz reprovava respostas corretas. Por isso cada criterio carrega o
# pedido original e as restricoes da sandbox (sem shell, sem escrita) no proprio corpo.
#
# PREFIXO `[trace]` num comportamento esperado: o criterio e' sobre o que o agente FEZ (ex.: qual
# skill chamou), nao sobre o que disse. Vira `focus: trace` — o juiz recebe a trajetoria em vez da
# ultima mensagem. E' o unico metadado por criterio; o schema autoral continua lista de strings.
#
# `--check` nao escreve nada e sai 1 se o que esta em disco divergir do que seria gerado. E' o
# que o CI roda: artefato gerado e commitado que envelhece em silencio e' pior que artefato
# ausente. Arquivo sobrando dentro de um caso (grader renomeado, fixture removida) conta como
# divergencia: grader orfao continua sendo executado e pontuado pelo host.

import argparse
import glob
import io
import json
import os
import re
import shutil
import sys

SKILLS_DIR = "plugins/lt/skills"
OUT_DIR = "plugins/lt/evals"
TRACE_PREFIX = "[trace]"

# A sandbox do caso so' tem ferramentas de leitura. Escrita e shell sao grants do operador
# (`--allow-tools`); sem eles o criterio que exige "roda X" ou "grava Y" e' impossivel, e o
# juiz precisa saber disso para nao cobrar o impossivel nem aceitar alegacao de execucao.
ALLOWED_TOOLS = ["Read", "Glob", "Grep", "Skill"]
SANDBOX_NOTE = (
    "O agente roda numa sandbox somente leitura: pode ler arquivos e invocar skills, mas não "
    "tem shell nem permissão de escrita. Comandos só podem ser indicados, nunca executados."
)


# Calibrado contra respostas reais com o mesmo juiz (haiku, prompt do host): com "PASS se o
# criterio e' cumprido de forma explicita", o juiz reprovava criterio negativo ("Nao ...")
# cumprido por ausencia e cobrava a conclusao do pedido inteiro em vez do criterio. Acerto
# medido subiu de 7/12 para 10/12 num conjunto com casos que devem passar e controles que devem
# reprovar — os controles continuaram reprovando.
JUDGE_SCOPE = (
    "Julgue apenas este critério — não a qualidade geral da resposta nem se o pedido foi "
    "concluído. Indicar o comando ou o plano conta como cumprir, porque a sandbox não permite "
    "executar. Um critério negativo (\"Não ...\") é cumprido quando a resposta não faz o que ele "
    "proíbe; ausência basta."
)


def slug(text):
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def is_negative(path):
    return bool(re.search(r"\d+-negativo-", os.path.basename(path)))


def build_case(skill, case_path, data):
    name = "%s--%s" % (skill, slug(os.path.basename(case_path)[:-5]))
    negative = is_negative(case_path)
    query = data.get("query", "")

    case = {
        "schema_version": "1.1",
        "name": name,
        "description": query[:200],
        "tags": ["negativo"] if negative else ["roteamento"],
        "execution": {
            # 8 turnos acabavam antes de a skill carregar, ler a fixture e responder.
            "max_turns": 10,
            "allowed_tools": ALLOWED_TOOLS,
        },
    }

    fixtures = [(f, os.path.join(SKILLS_DIR, skill, f)) for f in data.get("files", []) if f]

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
            body += ["min: 0", "max: 0"]
        else:
            body.append("min: 1")
        body += [
            "---",
            "",
            "A skill `%s` %s ser invocada neste cenario." % (
                declared, "NAO deve" if negative else "deve"),
            "",
            "Sob `--ablation with-without`, este grader vira indicador nao pontuado: sem o",
            "plugin carregado ele %s, entao pontua-lo compararia coisas diferentes." % (
                "passaria sempre" if negative else "nunca poderia passar"),
            "",
        ]
        graders["00-roteamento-%s.md" % declared] = "\n".join(body)

    for i, behavior in enumerate(data.get("expected_behavior", []), 1):
        text = behavior.strip()
        focus = "last_message"
        if text.startswith(TRACE_PREFIX):
            text = text[len(TRACE_PREFIX):].strip()
            focus = "trace"
        alvo = ("na trajetória do agente (chamadas de ferramenta e mensagens)"
                if focus == "trace" else "na resposta final do agente")
        graders["%02d-%s.md" % (i, slug(text)[:40])] = "\n".join([
            "---",
            "type: llm",
            "focus: %s" % focus,
            "---",
            "",
            "Critério a verificar %s:" % alvo,
            "",
            "> %s" % text,
            "",
            "Contexto, só para interpretar o critério (o juiz não recebe o pedido de outra forma): "
            "a pessoa usuária pediu \"%s\". %s" % (" ".join(query.split()), SANDBOX_NOTE),
            "",
            JUDGE_SCOPE,
            "",
        ])

    return name, case, graders, render_prompt(case_path, query, fixtures)


def render_prompt(case_path, query, fixtures):
    if not fixtures:
        return query.rstrip() + "\n"
    parts = [query.rstrip(), "",
             "O repositório não está disponível nesta sessão; o conteúdo atual dos arquivos citados "
             "vai abaixo.", ""]
    for rel, src in fixtures:
        if not os.path.isfile(src):
            sys.stderr.write("fixture ausente em %s: %s\n" % (case_path, src))
            raise SystemExit(1)
        with io.open(src, encoding="utf-8") as fh:
            body = fh.read().rstrip("\n")
        # Cerca mais longa que qualquer sequencia de crases da fixture, para nao fecha-la cedo.
        fence = "`" * max(3, max((len(m) for m in re.findall(r"`+", body)), default=0) + 1)
        parts += ["`%s`:" % rel, "", fence, body, fence, ""]
    return "\n".join(parts).rstrip() + "\n"


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
            files = {"case.yaml": render(case), "prompt.md": prompt}
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

    # Arquivo sobrando dentro de um caso: grader renomeado continua rodando e pontuando.
    for name, files in generated.items():
        base = os.path.join(OUT_DIR, name)
        expected = {os.path.normpath(os.path.join(base, rel)) for rel in files}
        for root, subdirs, names in os.walk(base, topdown=False):
            # `results/` e' saida do host quando o operador nao passa --output-dir.
            if os.path.relpath(root, base).split(os.sep)[0] == "results":
                continue
            for n in names:
                path = os.path.normpath(os.path.join(root, n))
                if path in expected:
                    continue
                if args.check:
                    diverged.append(path + " (sobra)")
                else:
                    os.remove(path)
            if not args.check and root != base and not os.listdir(root):
                os.rmdir(root)

    # Diretorio gerado que sobreviveu ao caso de origem seria um eval orfao rodando para sempre.
    if os.path.isdir(OUT_DIR):
        for existing in sorted(os.listdir(OUT_DIR)):
            if existing not in generated and os.path.isdir(os.path.join(OUT_DIR, existing)):
                if args.check:
                    diverged.append(os.path.join(OUT_DIR, existing) + " (orfao)")
                else:
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
