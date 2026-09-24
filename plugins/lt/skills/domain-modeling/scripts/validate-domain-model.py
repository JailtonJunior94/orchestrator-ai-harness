#!/usr/bin/env python3
"""Valida um domain-model.md gerado pela skill domain-modeling.

Uso:
    python3 validate-domain-model.py <caminho/domain-model.md>

Exit 0: imprime SUCCESS.
Exit 1: um erro por linha no stderr.
Exit 2: uso incorreto ou arquivo ilegível.
"""
import re
import sys

REQUIRED_SECTIONS = [
    "## Resumo",
    "## Escopo",
    "## Evidências",
    "## Linguagem Ubíqua",
    "## Bounded Contexts",
    "## Tipos do Domínio",
    "## Workflows",
    "## Eventos de Domínio",
    "## Invariantes e Regras",
    "## Erros de Domínio",
    "## Fronteiras e Persistência",
    "## Tradução para",
    "## Trade-offs e Decisões",
    "## Itens em Aberto",
]

STATUSES = ("draft", "done", "needs_input", "blocked")

# Travessão e meia-risca ficam fora por decisão de estilo do modelo: a pessoa pediu prosa sem
# travessão, e o validador é o único ponto que cobra isso de forma determinística.
DASHES = ("\u2014", "\u2013")

# Evidência confirmada precisa apontar arquivo e linha. Aceita `a/b.go:12` e `a/b.go:12-20`.
PATH_LINE = re.compile(r"[\w./-]+\.\w+:\d+")

# Placeholder do template é texto entre colchetes que não é link Markdown. Dentro de bloco de
# código, `map[string]int` e `[]T` são sintaxe legítima; ali só a linha inteira entre colchetes
# conta como placeholder, que é o formato que o template usa.
PLACEHOLDER_PROSE = re.compile(r"\[[^\]\n]+\](?!\()")
PLACEHOLDER_CODE = re.compile(r"^\s*\[[^\]]+\]\s*$")


def split_sections(text):
    sections = {}
    current = None
    for line in text.splitlines():
        if line.startswith("## "):
            current = line.strip()
            sections[current] = []
        elif current is not None:
            sections[current].append(line)
    return sections


def find_section(sections, heading):
    for name, body in sections.items():
        if name == heading or (heading.endswith(" para") and name.startswith(heading + " ")):
            return name, body
    return None, None


def check_placeholders(text, errors):
    in_code = False
    for number, line in enumerate(text.splitlines(), 1):
        if line.lstrip().startswith("```"):
            in_code = not in_code
            continue
        if line.lstrip().startswith("<!--"):
            continue
        if in_code:
            if PLACEHOLDER_CODE.match(line):
                errors.append("linha %d: placeholder do template não resolvido: %s" % (number, line.strip()))
        else:
            stripped = line.replace("\\|", "")
            match = PLACEHOLDER_PROSE.search(stripped)
            if match:
                errors.append("linha %d: placeholder do template não resolvido: %s" % (number, match.group(0)))


def check_evidence(body, errors):
    for line in body:
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 3 or cells[1].lower() != "confirmado":
            continue
        if not PATH_LINE.search(cells[2]):
            errors.append("## Evidências: achado confirmado sem path:linha: %s" % cells[0])


def validate(text):
    errors = []

    status = re.search(r"<!--\s*Status:\s*([\w_]+)\s*-->", text)
    if not status or status.group(1) not in STATUSES:
        errors.append("cabeçalho: falta <!-- Status: %s -->" % " | ".join(STATUSES))

    for dash in DASHES:
        for number, line in enumerate(text.splitlines(), 1):
            if dash in line:
                errors.append("linha %d: travessão ou meia-risca (U+%04X) não é permitido" % (number, ord(dash)))

    sections = split_sections(text)
    for heading in REQUIRED_SECTIONS:
        name, body = find_section(sections, heading)
        if name is None:
            errors.append("seção obrigatória ausente: %s" % heading)
            continue
        if not any(line.strip() for line in body):
            errors.append("seção vazia: %s" % name)

    _, types_body = find_section(sections, "## Tipos do Domínio")
    if types_body is not None and not any(re.match(r"\s*type\s+\w+", l) for l in types_body):
        errors.append("## Tipos do Domínio: nenhuma declaração `type Nome = ...`")

    # O Result na assinatura é o que separa workflow de procedimento: sem ele, a falha de negócio
    # não aparece no contrato e volta a ser exceção implícita.
    _, workflow_body = find_section(sections, "## Workflows")
    if workflow_body is not None and not any("Result<" in l for l in workflow_body):
        errors.append("## Workflows: nenhum workflow com saída Result<...>")

    _, evidence_body = find_section(sections, "## Evidências")
    if evidence_body is not None:
        check_evidence(evidence_body, errors)

    check_placeholders(text, errors)
    return errors


def main(argv):
    if len(argv) != 2:
        sys.stderr.write("uso: validate-domain-model.py <domain-model.md>\n")
        return 2
    try:
        with open(argv[1], encoding="utf-8") as handle:
            text = handle.read()
    except OSError as exc:
        sys.stderr.write("não foi possível ler %s: %s\n" % (argv[1], exc))
        return 2

    errors = validate(text)
    if errors:
        for error in errors:
            sys.stderr.write("ERRO: %s\n" % error)
        return 1
    print("SUCCESS")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
