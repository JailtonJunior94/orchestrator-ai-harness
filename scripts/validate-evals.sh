#!/usr/bin/env bash
# orchestrator-ai-harness / scripts / validate-evals.sh — banner: EVALS ESTATICOS OK
#
# Gate de CUSTO ZERO, roda em todo PR. Nao chama modelo nenhum.
#
# Responde as perguntas que nao precisam de modelo e que quebram em silencio: o caso aponta para
# uma skill que existe? a fixture que ele cita esta em disco? um caso negativo realmente afirma
# a recusa? os artefatos gerados ainda refletem os casos autorais?
#
# A logica de validacao vive em scripts/lib/validate-evals-cases.py, e nao num heredoc aqui
# dentro. A primeira versao era inline: o bloco imprimia as linhas de erro e este script seguia
# para o banner de sucesso. Separado, o codigo de saida propaga.

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

if [ -t 1 ]; then C_OK=$'\033[32m'; C_BAD=$'\033[31m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else C_OK=""; C_BAD=""; C_DIM=""; C_OFF=""; fi
OK=0; BAD=0
ok()  { OK=$((OK+1));  printf '  %s✓%s %s\n' "$C_OK" "$C_OFF" "$1"; }
bad() { BAD=$((BAD+1)); printf '  %s✗%s %s\n' "$C_BAD" "$C_OFF" "$1" >&2; }

command -v python3 >/dev/null 2>&1 || {
  # Gate que some junto com a dependencia e' verde por ausencia.
  printf 'python3 obrigatorio — este gate falha, nunca pula\n' >&2
  exit 2
}

printf '\n▸ casos autorais\n'
EVAL_OUT="$(python3 scripts/lib/validate-evals-cases.py 2>&1)"
EVAL_RC=$?

CASOS="$(printf '%s\n' "$EVAL_OUT" | sed -n 's/^CASOS=//p')"
NEG="$(printf '%s\n' "$EVAL_OUT" | sed -n 's/^NEGATIVOS=//p')"
FIX="$(printf '%s\n' "$EVAL_OUT" | sed -n 's/^FIXTURES=//p')"

while IFS= read -r line; do
  case "$line" in ERRO=*) bad "${line#ERRO=}" ;; esac
done <<EOF
$(printf '%s\n' "$EVAL_OUT")
EOF

if [ "$EVAL_RC" -eq 0 ]; then
  ok "schema, skills declaradas e fixtures conferem"
fi

printf '\n▸ cobertura\n'
[ "${CASOS:-0}" -ge 20 ] 2>/dev/null && ok "$CASOS casos autorais" || bad "apenas ${CASOS:-0} casos"
[ "${NEG:-0}" -ge 4 ] 2>/dev/null \
  && ok "$NEG casos negativos (a skill NAO deve disparar)" \
  || bad "apenas ${NEG:-0} casos negativos"
printf '  %s· %s fixture(s) resolvida(s) em disco%s\n' "$C_DIM" "${FIX:-0}" "$C_OFF"

printf '\n▸ artefatos gerados\n'
if python3 scripts/lib/evals-from-json.py --check >/dev/null 2>&1; then
  ok "plugins/lt/evals/ reflete os casos autorais"
else
  bad "plugins/lt/evals/ desatualizado — rode: python3 scripts/lib/evals-from-json.py"
fi

# Os dois defeitos que zeraram o primeiro baseline pago sem que nenhum gate estatico visse:
# roteamento negativo com a faixa `1..0` (so' `max: 0`; `min` tem default 1 no host) e
# `context.add_dirs`, que o host resolve relativo ao diretorio do caso e nunca anuncia ao agente.
NEG_RUIM=0
for g in plugins/lt/evals/*negativo*/graders/00-roteamento-*.md; do
  [ -f "$g" ] || continue
  if ! grep -q '^min: 0$' "$g" || ! grep -q '^max: 0$' "$g"; then NEG_RUIM=$((NEG_RUIM+1)); fi
done
[ "$NEG_RUIM" -eq 0 ] && ok "roteamento negativo com min: 0 e max: 0" \
  || bad "$NEG_RUIM grader(s) de roteamento negativo sem min: 0 + max: 0 — nunca passariam"
if grep -l 'add_dirs' plugins/lt/evals/*/case.yaml >/dev/null 2>&1; then
  bad "caso com context.add_dirs — o agente nao enxerga esse caminho; embuta a fixture no prompt"
else
  ok "nenhum caso depende de context.add_dirs"
fi

printf '\n▸ workflow de eval pago\n'
WF=".github/workflows/plugin-eval.yml"
if [ -f "$WF" ]; then
  if grep -qE '^\s*push:' "$WF"; then
    bad "dispara em push — eval e' pago, nao pode rodar em todo commit"
  else
    ok "nao dispara em push"
  fi
  grep -q 'max-cost-usd' "$WF" && ok "teto de custo presente" || bad "sem --max-cost-usd"
  grep -q -- '--json' "$WF" && ok "emite --json para analise posterior" || bad "sem --json"
else
  printf '  %s· %s ainda nao existe%s\n' "$C_DIM" "$WF" "$C_OFF"
fi

printf '\n%d ok · %d falha\n' "$OK" "$BAD"
if [ "$BAD" -eq 0 ]; then printf 'EVALS ESTATICOS OK\n'; exit 0; fi
printf 'EVALS ESTATICOS FALHOU\n' >&2
exit 1
