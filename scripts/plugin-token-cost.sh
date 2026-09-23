#!/usr/bin/env bash
# orchestrator-ai-harness / scripts / plugin-token-cost.sh
#
# Custo always-on do plugin: quantos tokens ele acrescenta a TODA sessao de quem o habilita.
#
# DONO UNICO DA MEDICAO. Este script e' o unico lugar que roda `claude plugin details` e extrai o
# numero; scripts/check-cost-baseline.sh (o ratchet que o CI roda) chama `--measure` daqui em vez
# de carregar uma segunda copia do parser. Duas copias do mesmo sed divergem no primeiro ajuste
# de formato do CLI, e uma delas passa a medir outra coisa em silencio.
#
# POR QUE HOME DESCARTAVEL
# Com ~/.claude populado o numero e' outro (o host soma o que ja esta instalado). A baseline so
# significa algo se toda medicao partir do mesmo estado vazio.
#
# FORMA DO COMANDO (docs/host-facts.md): `--plugin-dir` e' opcao GLOBAL, vai ANTES do
# subcomando. A forma que a propria mensagem de erro do host sugere falha.
#
# Uso:
#   bash scripts/plugin-token-cost.sh                  # ratchet (= scripts/check-cost-baseline.sh)
#   bash scripts/plugin-token-cost.sh --measure        # imprime so o numero de tokens always-on
#   bash scripts/plugin-token-cost.sh --write --cause "<por que o numero mudou>"
#   LT_DETAILS_OUTPUT=<arquivo>  usa uma saida gravada do `plugin details` (so para teste)
# Exit: 0 ok · 1 CLI ausente, saida ilegivel ou ratchet reprovado · 2 uso invalido

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASELINE="$ROOT/docs/benchmarks/plugin-token-cost.json"
PLUGIN_NAME="lt"
MODE="compare"
CAUSE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --compare) MODE="compare"; shift; case "${1:-}" in plugin-token-cost) shift ;; esac ;;
    --measure) MODE="measure"; shift ;;
    --write) MODE="write"; shift ;;
    --cause) CAUSE="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,24p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf 'flag desconhecida: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if [ "$MODE" = "compare" ]; then
  exec bash "$ROOT/scripts/check-cost-baseline.sh"
fi
if [ "$MODE" = "write" ] && [ -z "$CAUSE" ]; then
  printf 'uso: --write exige --cause "<por que o numero mudou>" — a causa vai para _history\n' >&2
  exit 2
fi

CLI_VERSION="n/a"
if [ -n "${LT_DETAILS_OUTPUT:-}" ]; then
  DETAILS="$(cat "$LT_DETAILS_OUTPUT")"
else
  # Gate que nao roda nao aprova: sem o CLI, isto e' falha, nao "pulado".
  command -v claude >/dev/null 2>&1 || { echo "FALHA: CLI 'claude' ausente; o custo nao foi medido" >&2; exit 1; }
  CLI_VERSION="$(claude --version 2>&1 | head -1 | sed 's/ .*//')"
  SCRATCH_HOME="$(mktemp -d)"
  trap 'rm -rf "$SCRATCH_HOME"' EXIT
  DETAILS="$(HOME="$SCRATCH_HOME" claude --plugin-dir "$ROOT/plugins/$PLUGIN_NAME" plugin details "$PLUGIN_NAME" 2>&1)" || true
fi

MEASURED="$(printf '%s\n' "$DETAILS" | sed -nE 's/.*Always-on:[[:space:]]*~?([0-9][0-9,]*)[[:space:]]*tok.*/\1/p' | head -1 | tr -d ',')"
if [ -z "$MEASURED" ]; then
  echo "FALHA: nao achei 'Always-on: ~N tok' na saida do plugin details" >&2
  printf '%s\n' "$DETAILS" | head -20 >&2
  exit 1
fi

if [ "$MODE" = "measure" ]; then
  printf '%s\n' "$MEASURED"
  exit 0
fi

# --write: regrava a baseline. Os contadores de componente vem do DISCO, nao do inventario do
# `plugin details` — ele soma commands dentro de "Skills" (docs/host-facts.md).
HOOK_EVENTS="$(printf '%s\n' "$DETAILS" | sed -nE 's/^[[:space:]]*Hooks \(([0-9]+)\).*/\1/p' | head -1)"
python3 - "$BASELINE" "$MEASURED" "${HOOK_EVENTS:-0}" "$CLI_VERSION" "$CAUSE" "$ROOT/plugins/$PLUGIN_NAME" "$PLUGIN_NAME" <<'PY'
import datetime
import glob
import json
import os
import sys

path, measured, hook_events, cli, cause, plugin, name = sys.argv[1:8]
old = {}
if os.path.isfile(path):
    try:
        old = json.load(open(path, encoding="utf-8"))
    except ValueError:
        old = {}
today = datetime.date.today().isoformat()
history = old.get("_history") if isinstance(old.get("_history"), list) else []
history.append({"date": today, "always_on_tokens": int(measured), "cause": cause})
out = {
    "_cli": cli,
    "_command": "HOME=$(mktemp -d) claude --plugin-dir <abs> plugin details %s" % name,
    "_home": "disposable",
    "_measured_at": today,
    "_note": "Ratchet guardado por scripts/check-cost-baseline.sh no job de host do CI. Subir a baseline exige regravar com scripts/plugin-token-cost.sh --write --cause no mesmo PR.",
    "plugins": {
        name: {
            "always_on_tokens": int(measured),
            "agents": len(glob.glob(os.path.join(plugin, "agents", "*.md"))),
            "commands": len(glob.glob(os.path.join(plugin, "commands", "*.md"))),
            "hook_events": int(hook_events),
            "skills": len(glob.glob(os.path.join(plugin, "skills", "*", "SKILL.md"))),
        }
    },
    "_history": history,
}
with open(path + ".tmp", "w", encoding="utf-8") as fh:
    json.dump(out, fh, ensure_ascii=False, indent=2)
    fh.write("\n")
os.replace(path + ".tmp", path)
print("baseline regravada: %s tok (%s)" % (measured, os.path.relpath(path)))
PY
