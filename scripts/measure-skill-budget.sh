#!/usr/bin/env bash
# orchestrator-ai-harness / scripts / measure-skill-budget.sh
#
# Mede quanto do orcamento de listagem de skills o plugin consome, e trava a subida.
#
# O MODELO DO HOST
# Toda sessao recebe, para cada skill (e cada command, que o host lista junto — ver
# docs/host-facts.md, "Comando aparece como Skill no inventario"), o `description` e o
# `when_to_use`. O espaco e' finito:
#
#     budget_chars = context_window * 4 * skillListingBudgetFraction
#
# e e' COMPARTILHADO com tudo o que cada pessoa instala por conta propria. Ao estourar, o host
# descarta descriptions das skills menos usadas primeiro — e skill sem description nao e'
# descoberta. O plugin nao controla o total da maquina; controla a propria parte dele.
#
# DUAS REGUAS, DE NATUREZA DIFERENTE
#   per-item  description + when_to_use <= 1536 chars (skillListingMaxDescChars). ABSOLUTO: o
#             host trunca acima disso, entao passar do cap e' defeito, nao escolha.
#   agregado  RATCHET contra docs/benchmarks/skill-listing.json. Subir exige regravar a baseline
#             no mesmo PR (--write --cause), com a justificativa tambem no corpo do PR. Ratchet
#             regravado sem motivo e' o mesmo que nao ter ratchet.
#
# A FRACAO: enterprise/managed-settings.json NAO define skillListingBudgetFraction (a chave nao
# esta na referencia oficial de settings e enterprise/verify.sh reprova quem a usar). Portanto
# a conta usa o default do host, e a baseline registra isso em `_fraction_source`.
#
# CONTAGEM EM CODE POINTS (python len()), nao `wc -m`: `wc -m` muda de resultado entre
# LC_ALL=C e UTF-8, e uma description com acento media diferente no CI e no Mac.
#
# Uso:
#   bash scripts/measure-skill-budget.sh                 # ratchet (padrao; alias: --compare)
#   bash scripts/measure-skill-budget.sh --print         # so mede, nao compara
#   bash scripts/measure-skill-budget.sh --write --cause "<por que o numero mudou>"
# Exit: 0 ok · 1 cap estourado, agregado subiu ou baseline desatualizada · 2 uso invalido

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASELINE="$ROOT/docs/benchmarks/skill-listing.json"
PLUGIN="$ROOT/plugins/lt"
MODE="compare"
CAUSE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --compare) MODE="compare"; shift; case "${1:-}" in skill-listing) shift ;; esac ;;
    --print) MODE="print"; shift ;;
    --write) MODE="write"; shift ;;
    --cause) CAUSE="${2:-}"; shift 2 ;;
    --baseline) BASELINE="$2"; shift 2 ;;
    --plugin) PLUGIN="$2"; shift 2 ;;
    -h|--help) sed -n '2,36p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf 'flag desconhecida: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if [ "$MODE" = "write" ] && [ -z "$CAUSE" ]; then
  printf 'uso: --write exige --cause "<por que o numero mudou>" — a causa vai para _history\n' >&2
  exit 2
fi

exec python3 - "$PLUGIN" "$BASELINE" "$MODE" "$CAUSE" <<'PY'
import datetime
import glob
import json
import os
import sys

plugin, baseline_path, mode, cause = sys.argv[1:5]

try:
    import yaml
except ImportError:
    print("FALHA: PyYAML ausente — a medicao FALHA, nunca pula")
    sys.exit(1)

MAX_ITEM = 1536
# Default do host para skillListingBudgetFraction, e janela de referencia de 200k tokens.
FRACTION = 0.01
WINDOW = 200000
WARN_PCT = 60


def frontmatter(path):
    text = open(path, encoding="utf-8").read()
    if not text.startswith("---"):
        return {}
    block = text.split("\n---", 1)[0][3:]
    data = yaml.safe_load(block) or {}
    return data if isinstance(data, dict) else {}


items = {}
for p in sorted(glob.glob(os.path.join(plugin, "skills", "*", "SKILL.md"))):
    d = frontmatter(p)
    name = d.get("name") or os.path.basename(os.path.dirname(p))
    items[str(name)] = len(str(d.get("description") or "")) + len(str(d.get("when_to_use") or ""))
for p in sorted(glob.glob(os.path.join(plugin, "commands", "*.md"))):
    d = frontmatter(p)
    name = os.path.splitext(os.path.basename(p))[0]
    items[name] = len(str(d.get("description") or "")) + len(str(d.get("when_to_use") or ""))

if not items:
    print("FALHA: nenhuma skill nem command descoberto em %s" % plugin)
    sys.exit(1)

total = sum(items.values())
budget = int(WINDOW * 4 * FRACTION)
pct = round(100.0 * total / budget, 1)

fail = 0
for name, chars in sorted(items.items()):
    if chars > MAX_ITEM:
        print("FALHA: %s tem %d chars de listagem (cap absoluto do host: %d)" % (name, chars, MAX_ITEM))
        fail += 1

print("listagem: %d item(ns), %d chars, %.1f%% de %d (fracao %.2f, janela %dk)"
      % (len(items), total, pct, budget, FRACTION, WINDOW // 1000))
if pct >= WARN_PCT:
    print("aviso: acima de %d%% do orcamento default — o que cada pessoa instala por fora disputa o resto" % WARN_PCT)

if mode == "print":
    for name, chars in sorted(items.items()):
        print("  %-34s %5d" % (name, chars))
    sys.exit(1 if fail else 0)

if mode == "write":
    if fail:
        print("FALHA: nao regravo baseline com item acima do cap absoluto")
        sys.exit(1)
    old = {}
    if os.path.isfile(baseline_path):
        try:
            old = json.load(open(baseline_path, encoding="utf-8"))
        except ValueError:
            old = {}
    history = old.get("_history") if isinstance(old.get("_history"), list) else []
    today = datetime.date.today().isoformat()
    history.append({"date": today, "total_chars": total, "cause": cause})
    out = {
        "_budget_model": "budget_chars = context_window * 4 * skillListingBudgetFraction",
        "_fraction_source": "default do host; enterprise/managed-settings.json nao define skillListingBudgetFraction (chave fora da referencia oficial, reprovada por enterprise/verify.sh)",
        "_measured_at": today,
        "_measured_with": "scripts/measure-skill-budget.sh --write (python len(), code points; independe de LC_ALL)",
        "_note": "per_item e' ABSOLUTO (cap do host skillListingMaxDescChars = 1536). total_chars e' RATCHET: subir exige --write --cause no mesmo PR e justificativa no corpo do PR. Commands entram porque o host os lista junto com as skills.",
        "budget_chars_at_200k": budget,
        "fraction": FRACTION,
        "pct_of_budget": pct,
        "warn_at_pct": WARN_PCT,
        "per_item": dict(sorted(items.items())),
        "total_chars": total,
        "_history": history,
    }
    with open(baseline_path + ".tmp", "w", encoding="utf-8") as fh:
        json.dump(out, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    os.replace(baseline_path + ".tmp", baseline_path)
    print("baseline regravada: %s (%d chars)" % (os.path.relpath(baseline_path), total))
    sys.exit(0)

# --- compare (ratchet) ---
if not os.path.isfile(baseline_path):
    print("FALHA: baseline ausente: %s (gere com --write --cause)" % baseline_path)
    sys.exit(1)
base = json.load(open(baseline_path, encoding="utf-8"))
base_items = base.get("per_item")
if not isinstance(base_items, dict):
    print("FALHA: baseline sem per_item — formato antigo; regrave com --write --cause")
    sys.exit(1)
want = int(base.get("total_chars", -1))

gone = sorted(set(base_items) - set(items))
new = sorted(set(items) - set(base_items))
if gone or new:
    # Baseline que lista o que nao existe (ou ignora o que existe) compara contra ficcao: o total
    # dela nao significa nada e o ratchet trava contra um numero inventado.
    if gone:
        print("FALHA: baseline lista item que nao existe mais: %s" % ", ".join(gone))
    if new:
        print("FALHA: item em disco ausente da baseline: %s" % ", ".join(new))
    fail += 1

for name in sorted(set(items) & set(base_items)):
    delta = items[name] - int(base_items[name])
    if delta:
        print("  %s: %+d chars" % (name, delta))

if total > want:
    print("FALHA: listagem subiu: medido %d chars, baseline %d (+%d)." % (total, want, total - want))
    print("  Se e' intencional: --write --cause \"...\" no mesmo PR, e a justificativa no corpo do PR.")
    fail += 1
elif total < want:
    print("ok: medido %d chars, abaixo da baseline %d. Regrave com --write: o ratchet so anda para baixo." % (total, want))
else:
    print("ok: listagem %d chars, igual a baseline" % total)

if fail:
    print("SKILL BUDGET FALHOU")
    sys.exit(1)
print("SKILL BUDGET OK")
PY
