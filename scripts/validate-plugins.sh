#!/usr/bin/env bash
# orchestrator-ai-harness / scripts / validate-plugins.sh
#
# Gate do host: `claude plugin validate` no manifesto do marketplace e em cada plugin declarado
# nele, com os avisos aceitos de proposito filtrados por config/validate-allowlist.txt.
#
# POR QUE --json E NAO --strict
# Com --strict o host reprova qualquer aviso, inclusive o `cadence` que a allowlist aceita — o
# gate ficaria vermelho para sempre ou teria de pular o manifesto. Com --json o relatorio vem
# estruturado (errors[] e warnings[] por arquivo), e a severidade estrita e' aplicada AQUI:
# todo aviso reprova, exceto o que casa um padrao vivo da allowlist. Parsear a saida humana
# (o "❯ ...") quebraria no primeiro ajuste cosmetico do CLI.
#
# AS TRES FALHAS DA ALLOWLIST (cabecalho de config/validate-allowlist.txt):
#   1. aviso do host que NAO casa nenhum padrao listado;
#   2. padrao listado que DEIXOU de aparecer — o host passou a entender o campo e a entrada
#      virou mentira;
#   3. data de revisao vencida. Allowlist sem caducidade vira desculpa permanente.
#
# GATE QUE NAO RODA NAO APROVA: sem o CLI, isto e' FALHA (exit 1), nunca "pulado". Um job de CI
# que perde a dependencia e continua verde e' o falso-verde mais barato que existe.
#
# Uso:  bash scripts/validate-plugins.sh
#   LT_CLAUDE_BIN=<bin>   CLI alternativo (teste com binario falso)
#   LT_TODAY=YYYY-MM-DD   data de referencia para a caducidade (teste)
# Exit: 0 limpo · 1 reprovado ou CLI ausente

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CLAUDE_BIN="${LT_CLAUDE_BIN:-claude}"
ALLOWLIST="$ROOT/config/validate-allowlist.txt"
MANIFEST=".claude-plugin/marketplace.json"
TODAY="${LT_TODAY:-$(date -u +%Y-%m-%d)}"

if ! command -v "$CLAUDE_BIN" >/dev/null 2>&1; then
  printf 'FALHA: CLI %s ausente — o gate de validacao do host NAO rodou\n' "$CLAUDE_BIN" >&2
  exit 1
fi
command -v python3 >/dev/null 2>&1 || { printf 'FALHA: python3 ausente\n' >&2; exit 1; }

# O cabecalho com a versao do CLI e' evidencia: quando um aviso novo aparece, a primeira
# pergunta e' "qual versao do host passou a emitir isso?".
printf '── validate-plugins · %s\n' "$("$CLAUDE_BIN" --version 2>&1 | head -1)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Alvos: o manifesto e todo `source` declarado nele. Lido do manifesto, nunca de lista fixa —
# plugin novo que ninguem lembrou de acrescentar aqui ficaria sem validacao, verde por ausencia.
TARGETS="$MANIFEST"
while IFS= read -r src; do
  [ -n "$src" ] || continue
  TARGETS="$TARGETS
${src#./}"
done <<EOF
$(python3 -c 'import json,sys; [print(p.get("source","")) for p in json.load(open(sys.argv[1]))["plugins"]]' "$MANIFEST")
EOF

N=0
while IFS= read -r target; do
  [ -n "$target" ] || continue
  N=$((N+1))
  out="$WORK/report-$N.json"
  # O exit do CLI nao decide nada sozinho: sem --strict ele sai 0 com aviso, e o que importa
  # e' o conteudo do relatorio. Um exit != 0 com JSON ilegivel e' tratado abaixo como falha.
  set +e
  "$CLAUDE_BIN" plugin validate "$target" --json >"$out" 2>"$WORK/stderr-$N.txt"
  rc=$?
  set -e
  printf '%s\t%s\t%s\n' "$target" "$rc" "$out" >> "$WORK/index.tsv"
done <<EOF
$TARGETS
EOF

exec python3 - "$ALLOWLIST" "$TODAY" "$WORK/index.tsv" <<'PY'
import json
import re
import sys

allowlist_path, today, index_path = sys.argv[1], sys.argv[2], sys.argv[3]

allow = []
fail = 0
with open(allowlist_path, encoding="utf-8") as fh:
    for lineno, raw in enumerate(fh, 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = [p.strip() for p in line.split(" | ")]
        if len(parts) != 4:
            print("FALHA: allowlist:%d fora do formato <regex> | <motivo> | <owner> | <data>" % lineno)
            fail += 1
            continue
        pattern, _motivo, owner, until = parts
        if not re.match(r"^\d{4}-\d{2}-\d{2}$", until):
            print("FALHA: allowlist:%d data de revisao invalida: %s" % (lineno, until))
            fail += 1
            continue
        if until < today:
            print("FALHA: allowlist:%d venceu em %s (owner %s) — revise ou remova" % (lineno, until, owner))
            fail += 1
        allow.append({"regex": re.compile(pattern), "raw": pattern, "hits": 0})


def findings(node, sink):
    """Coleta errors/warnings de qualquer nivel do relatorio (manifesto e contents[])."""
    if isinstance(node, dict):
        where = node.get("file") or node.get("path") or "?"
        for kind in ("errors", "warnings"):
            for item in node.get(kind) or []:
                if isinstance(item, dict):
                    text = "%s: %s" % (item.get("path") or "", item.get("message") or "")
                else:
                    text = str(item)
                sink.append((kind, where, text.strip(": ")))
        for value in node.values():
            if isinstance(value, (dict, list)):
                findings(value, sink)
    elif isinstance(node, list):
        for value in node:
            findings(value, sink)


with open(index_path, encoding="utf-8") as fh:
    rows = [line.rstrip("\n").split("\t") for line in fh if line.strip()]

for target, rc, report in rows:
    try:
        data = json.load(open(report, encoding="utf-8"))
    except (IOError, OSError, ValueError):
        print("FALHA: %s — relatorio --json ilegivel (exit %s); o CLI mudou a forma da saida?" % (target, rc))
        fail += 1
        continue
    sink = []
    findings(data, sink)
    target_bad = 0
    for kind, where, text in sink:
        if kind == "errors":
            print("FALHA: %s — erro do host: %s" % (target, text))
            target_bad += 1
            continue
        matched = [a for a in allow if a["regex"].search(text)]
        if matched:
            for a in matched:
                a["hits"] += 1
            print("  ~ %s — aviso aceito pela allowlist: %s" % (target, text))
        else:
            print("FALHA: %s — aviso fora da allowlist: %s" % (target, text))
            target_bad += 1
    if data.get("success") is False and not target_bad:
        print("FALHA: %s — host reportou success=false sem erro legivel" % target)
        target_bad += 1
    if not target_bad:
        print("  ✓ %s" % target)
    fail += target_bad

for a in allow:
    if a["hits"] == 0:
        # Caducidade por desuso: o aviso sumiu, a entrada tem de sair junto.
        print("FALHA: padrao da allowlist deixou de aparecer — remova-o: %s" % a["raw"])
        fail += 1

if fail:
    print("\nVALIDATE FALHOU (%d problema(s))" % fail)
    sys.exit(1)
print("\nVALIDATE PASSOU (%d alvo(s))" % len(rows))
PY
