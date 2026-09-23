#!/usr/bin/env bash
# scripts / check-cost-baseline.sh
#
# Ratchet do custo always-on do plugin: mede com `claude plugin details` sob HOME descartavel e
# compara com docs/benchmarks/plugin-token-cost.json.
#
# POR QUE EXISTE
# A baseline se declarava "ratchet", mas o CI so' imprimia a medicao ao lado dela. Entre a
# gravacao (2.582 tok) e a validacao seguinte o custo subiu para 2.674 e nada acusou. A causa
# era legitima (tres commands ganharam `description`), mas ninguem decidiu: foi so' acontecendo.
# Ratchet que nao compara nao trava nada.
#
# REGRAS
#   medido >  baseline -> FALHA. Subir exige regravar no mesmo PR (plugin-token-cost.sh --write --cause).
#   medido <  baseline -> passa, e avisa para baixar a baseline (o ratchet so' anda para baixo).
#   medido == baseline -> passa.
# A medicao e' sempre sob HOME descartavel: com ~/.claude populado o numero e' outro.
#
# Uso:  bash scripts/check-cost-baseline.sh
#   LT_DETAILS_OUTPUT=<arquivo>  usa uma saida gravada em vez de rodar o CLI (so' para teste).
#   Para regravar a baseline: scripts/plugin-token-cost.sh --write --cause "..."
# Exit: 0 ok · 1 subiu, CLI ausente ou saida ilegivel

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASELINE="$ROOT/docs/benchmarks/plugin-token-cost.json"

# A medicao mora em scripts/plugin-token-cost.sh (dono unico do parser do `plugin details`).
# Este script so compara. LT_DETAILS_OUTPUT atravessa pelo ambiente.
MEASURED="$(bash "$ROOT/scripts/plugin-token-cost.sh" --measure)" || exit 1

WANT="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["plugins"]["lt"]["always_on_tokens"])' "$BASELINE")"

if [ "$MEASURED" -gt "$WANT" ]; then
  echo "FALHA: custo always-on subiu: medido $MEASURED tok, baseline $WANT tok (+$((MEASURED - WANT)))." >&2
  echo "  Se a subida e' intencional, regrave no mesmo PR com" >&2
  echo "  bash scripts/plugin-token-cost.sh --write --cause \"<motivo>\" (a causa vai para _history)." >&2
  echo "  Sem isso o ratchet nao trava nada." >&2
  exit 1
fi
if [ "$MEASURED" -lt "$WANT" ]; then
  echo "ok: medido $MEASURED tok, abaixo da baseline $WANT. Baixe a baseline para $MEASURED (plugin-token-cost.sh --write --cause): o ratchet so' anda para baixo."
  exit 0
fi
echo "ok: custo always-on $MEASURED tok, igual a baseline"
