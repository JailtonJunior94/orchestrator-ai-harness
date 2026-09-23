#!/usr/bin/env bash
# orchestrator-ai-harness / scripts / check-eval-routing.sh
#
# Le o --json de um run de eval e responde a UMA pergunta: a skill disparou quando deveria, e
# ficou calada quando nao deveria?
#
# NAO FALHA POR NOTA. Nota baixa e' informacao sobre qualidade da resposta; roteamento quebrado
# e' a skill deixando de existir na pratica. Sao coisas diferentes, e misturar as duas faz o
# time ignorar as duas.
#
# Delta negativo tambem NAO falha: pode ser variacao do modelo, do caso, ou do dia.

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

def walk(node, out):
    """O formato exato do relatorio pode variar entre versoes do CLI. Em vez de assumir uma
    forma, procuramos graders de roteamento onde quer que estejam — e se nao acharmos nenhum,
    dizemos isso em vez de devolver verde."""
    if isinstance(node, dict):
        name = str(node.get("name") or node.get("grader") or "")
        if "roteamento" in name.lower() or node.get("type") == "tool_used":
            out.append(node)
        for v in node.values():
            walk(v, out)
    elif isinstance(node, list):
        for v in node:
            walk(v, out)

graders = []
walk(data, graders)

if not graders:
    sys.stderr.write(
        "[lt] nenhum grader de roteamento encontrado no relatorio.\n"
        "     Isso nao e' 'tudo certo': ou o formato mudou, ou os casos perderam o grader.\n"
    )
    raise SystemExit(1)

quebrados = []
for g in graders:
    passed = g.get("passed")
    if passed is None:
        passed = g.get("result") in ("pass", "passed", True)
    if not passed:
        quebrados.append(g.get("name") or g.get("grader") or "?")

print("graders de roteamento avaliados: %d" % len(graders))
if quebrados:
    sys.stderr.write("[lt] ROTEAMENTO QUEBRADO em %d grader(es):\n" % len(quebrados))
    for q in quebrados[:10]:
        sys.stderr.write("  - %s\n" % q)
    sys.stderr.write("\n  A skill deixou de disparar quando deveria (ou disparou quando nao deveria).\n")
    raise SystemExit(1)

print("roteamento intacto: toda skill disparou quando deveria e calou quando nao deveria")
PYEOF
