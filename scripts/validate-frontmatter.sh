#!/usr/bin/env bash
# orchestrator-ai-harness / scripts / validate-frontmatter.sh
#
# Frontmatter de todo componente de plugin (skills/*/SKILL.md, agents/*.md, commands/*.md,
# output-styles/*.md) na forma que o HOST aceita — nao na forma que o YAML "tolera".
#
# POR QUE O HOST E NAO O YAML E' A REGUA (ver CLAUDE.md §3)
#   - `description` em escalar de bloco (`|` ou `>`): o host DESCARTA O FRONTMATTER INTEIRO e o
#     componente passa a anunciar o primeiro titulo do corpo como descricao. Nao da erro.
#   - `argument-hint: [slug]` parseia como LISTA. O host espera texto; aspas sempre.
#   - escalar plano que comeca por `[ { * & ! % @` ou contem `: ` quebra o YAML; com
#     `description` plana o host repara em silencio, o que esconde o defeito ate outro parser ler.
#
# CODIGOS
#   E0 sem bloco de frontmatter            E1 YAML estrito rejeita
#   E2 chave de texto lida como outro tipo (lista, mapa, numero) ou argument-hint sem aspas
#   E3 description ausente, vazia ou em escalar de bloco
#   E4 name fora de kebab ASCII, ou divergente do diretorio/arquivo
#   E5 description + when_to_use acima de 1536 chars (skillListingMaxDescChars do host)
#   E6 description que nao le como pt-BR (heuristica de palavras funcionais)
#
# E6 mora AQUI e so aqui: tests/language-policy-check.sh chama este script com --language-only em
# vez de carregar uma segunda copia da heuristica. Uma regra, um dono.
#
# SEM PyYAML ISTO FALHA (exit 1), NUNCA PULA. Validador cuja dependencia sumiu e que sai verde e'
# o falso-verde que este repo ja pagou em outros gates.
#
# Uso:  bash scripts/validate-frontmatter.sh [--language-only] [raiz-de-plugins]
# Exit: 0 limpo · 1 algum componente reprovou, zero componentes ou PyYAML ausente · 2 uso

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="full"
PLUGINS_DIR="$ROOT/plugins"

while [ $# -gt 0 ]; do
  case "$1" in
    --language-only) MODE="language"; shift ;;
    -h|--help) printf 'uso: validate-frontmatter.sh [--language-only] [raiz-de-plugins]\n'; exit 0 ;;
    -*) printf 'flag desconhecida: %s\n' "$1" >&2; exit 2 ;;
    *) PLUGINS_DIR="$1"; shift ;;
  esac
done

[ -d "$PLUGINS_DIR" ] || { printf 'FALHA: diretorio de plugins inexistente: %s\n' "$PLUGINS_DIR" >&2; exit 1; }

exec python3 - "$PLUGINS_DIR" "$MODE" <<'PY'
import glob
import os
import re
import sys
import unicodedata

plugins_dir, mode = sys.argv[1], sys.argv[2]

try:
    import yaml
except ImportError:
    print("FALHA: PyYAML ausente — este gate FALHA, nunca pula (pip install pyyaml)")
    sys.exit(1)

KEBAB = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
TEXT_KEYS = ("name", "description", "when_to_use", "argument-hint", "model", "effort")
MAX_LISTING = 1536

# Palavras funcionais sem acento. Ficam de fora as ambiguas entre as duas linguas ("a", "no",
# "use", "as"): contariam para os dois lados e so' adicionariam ruido.
PT = set("""de da do das dos para quando nao com sem em um uma que ou por pela pelo ao aos
se ja mais antes depois ate como sobre entre cada quem qual precisa precisar e""".split())
EN = set("""the and when with for to of is this that it be or not from by on in are should
must""".split())


def fold(text):
    norm = unicodedata.normalize("NFKD", text)
    return "".join(c for c in norm if not unicodedata.combining(c)).lower()


# Diacriticos que o ingles nao usa: descricao curta ("Diagnostico do harness — versoes,
# instalacao") tem poucas palavras funcionais, mas carrega o idioma nos acentos.
PT_MARKS = re.compile("[\u00e3\u00f5\u00e7\u00e2\u00ea\u00f4\u00e1\u00e9\u00ed\u00f3\u00fa\u00e0]")


def reads_as_ptbr(text):
    words = re.findall(r"[a-z]+", fold(text))
    pt = sum(1 for w in words if w in PT)
    pt += sum(1 for w in re.findall(r"\w+", text.lower()) if PT_MARKS.search(w))
    en = sum(1 for w in words if w in EN)
    if en == 0:
        return pt >= 1, pt, en
    return pt >= 3 and pt >= 2 * en, pt, en


def discover():
    found = []
    for p in sorted(glob.glob(os.path.join(plugins_dir, "*", "skills", "*", "SKILL.md"))):
        found.append(("skill", p, os.path.basename(os.path.dirname(p))))
    for kind, sub in (("agent", "agents"), ("command", "commands"), ("output-style", "output-styles")):
        for p in sorted(glob.glob(os.path.join(plugins_dir, "*", sub, "*.md"))):
            if os.path.basename(p).lower() == "readme.md":
                continue
            found.append((kind, p, os.path.splitext(os.path.basename(p))[0]))
    return found


def split_frontmatter(text):
    if not text.startswith("---"):
        return None
    parts = text.split("\n---", 1)
    if len(parts) < 2:
        return None
    return parts[0][3:].lstrip("\n")


def raw_value(block, key):
    m = re.search(r"^%s:[ \t]*(.*)$" % re.escape(key), block, re.MULTILINE)
    return None if m is None else m.group(1).strip()


components = discover()
if not components:
    # Zero descobertos e' erro: um glob quebrado nao pode virar "tudo valido".
    print("FALHA: nenhum componente descoberto em %s" % plugins_dir)
    sys.exit(1)

errors = 0
rel_base = os.path.dirname(os.path.abspath(plugins_dir))


def report(code, path, msg):
    global errors
    errors += 1
    print("FALHA %s %s: %s" % (code, os.path.relpath(path, rel_base), msg))


for kind, path, stem in components:
    text = open(path, encoding="utf-8").read()
    block = split_frontmatter(text)
    if block is None:
        report("E0", path, "sem bloco de frontmatter delimitado por ---")
        continue
    try:
        data = yaml.safe_load(block) or {}
    except yaml.YAMLError as exc:
        report("E1", path, "YAML estrito rejeita: %s" % str(exc).splitlines()[0])
        continue
    if not isinstance(data, dict):
        report("E1", path, "frontmatter nao e' um mapa")
        continue

    name = data.get("name")
    desc = data.get("description")

    if mode == "full":
        for key in TEXT_KEYS:
            if key in data and not isinstance(data[key], str):
                hint = ' (aspe: %s: "...")' % key if isinstance(data[key], list) else ""
                report("E2", path, "%s lido como %s, nao texto%s" % (key, type(data[key]).__name__, hint))
        raw_hint = raw_value(block, "argument-hint")
        if raw_hint and raw_hint[0] not in "\"'":
            report("E2", path, "argument-hint sem aspas: %s" % raw_hint)

        raw_desc = raw_value(block, "description")
        if raw_desc is not None and raw_desc[:1] in ("|", ">"):
            report("E3", path, "description em escalar de bloco — o host descarta o frontmatter inteiro")
        elif not isinstance(desc, str) or not desc.strip():
            report("E3", path, "description ausente ou vazia")

        if kind in ("skill", "agent"):
            if not isinstance(name, str) or not KEBAB.match(name):
                report("E4", path, "name ausente ou fora de kebab ASCII: %r" % (name,))
            elif kind == "skill" and name != stem:
                report("E4", path, "name '%s' != diretorio '%s'" % (name, stem))
        if kind in ("skill", "command") and not KEBAB.match(stem):
            report("E4", path, "nome de %s fora de kebab ASCII: %s" % (kind, stem))

        if isinstance(desc, str):
            total = len(desc) + len(data.get("when_to_use") or "")
            if total > MAX_LISTING:
                report("E5", path, "description + when_to_use = %d chars (cap do host %d)" % (total, MAX_LISTING))

    if isinstance(desc, str) and desc.strip():
        ok, pt, en = reads_as_ptbr(desc)
        if not ok:
            report("E6", path, "description nao le como pt-BR (%d marcadores pt, %d en)" % (pt, en))
    if mode == "language" and kind in ("skill", "agent") and name is not None:
        if not isinstance(name, str) or not KEBAB.match(name):
            report("E4", path, "name fora de kebab ASCII: %r" % (name,))

if errors:
    print("\nFRONTMATTER REPROVADO: %d problema(s) em %d componente(s)" % (errors, len(components)))
    sys.exit(1)
label = "IDIOMA DO FRONTMATTER OK" if mode == "language" else "FRONTMATTER OK"
print("%s: %d componente(s)" % (label, len(components)))
PY
