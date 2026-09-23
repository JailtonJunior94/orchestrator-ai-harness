#!/usr/bin/env bash
# orchestrator-ai-harness / scripts / pilot-check.sh
#
# Agregador local. Roda tudo que o CI roda, guarda evidencia em disco e so apaga quando passa.
#
# DUAS REGRAS QUE MUDAM O RESULTADO:
#
# 1. SUITE E' GATEADA PELO BANNER, nao so pelo exit code. Um `set -e` mal posto devolve 0 com
#    metade dos testes pulados; o banner so sai no fim, entao ele prova que a suite chegou ao fim.
#
# 2. `exit 2` (nao conseguiu rodar) e' DIFERENTE de `exit 1` (rodou e reprovou). Dependencia
#    ausente vira amarelo contado, nunca verde silencioso — gate que some junto com a dependencia
#    e' verde por ausencia.

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

if [ -t 1 ]; then C_OK=$'\033[32m'; C_BAD=$'\033[31m'; C_WARN=$'\033[33m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else C_OK=""; C_BAD=""; C_WARN=""; C_DIM=""; C_OFF=""; fi
PASS=0; FAIL=0; BLOCKED=0
EVID="$(mktemp -d)"
sec()  { printf '\n%s──%s %s\n' "$C_DIM" "$C_OFF" "$1"; }
ok()   { PASS=$((PASS+1));    printf '  %s✓%s %s\n' "$C_OK" "$C_OFF" "$1"; }
bad()  { FAIL=$((FAIL+1));    printf '  %s✗%s %s\n' "$C_BAD" "$C_OFF" "$1" >&2; }
warn() { BLOCKED=$((BLOCKED+1)); printf '  %s~%s %s\n' "$C_WARN" "$C_OFF" "$1"; }

# tiered_check <rotulo> <banner-esperado|-> <comando...>
tiered_check() {
  label="$1"; banner="$2"; shift 2
  out="$EVID/$(printf '%s' "$label" | tr ' /' '__').log"
  "$@" >"$out" 2>&1
  rc=$?
  if [ "$rc" -eq 127 ] || [ "$rc" -eq 2 ]; then
    warn "$label: nao conseguiu rodar (exit $rc) — evidencia: $out"
    return 0
  fi
  if [ "$rc" -ne 0 ]; then
    bad "$label: reprovou (exit $rc)"
    printf '%s\n' "     evidencia: $out" >&2
    grep -E '✗|FAIL|Error|falha|FALHOU' "$out" | tail -8 | sed 's/^/       /' >&2
    return 0
  fi
  if [ "$banner" != "-" ] && ! grep -q "$banner" "$out"; then
    # Exit 0 sem o banner: a suite terminou cedo. E' o falso-verde mais comum.
    bad "$label: exit 0 mas SEM o banner '$banner' — a suite nao chegou ao fim"
    printf '%s\n' "     evidencia: $out" >&2
    return 0
  fi
  ok "$label"
}

printf '\n%sorchestrator-ai-harness · pilot-check%s\n' "$C_DIM" "$C_OFF"
printf '%sevidencia em %s%s\n' "$C_DIM" "$EVID" "$C_OFF"

sec "1 · dependencias"
for t in python3 jq git bash; do
  command -v "$t" >/dev/null 2>&1 && ok "$t" || bad "$t ausente"
done
if command -v claude >/dev/null 2>&1; then
  ok "claude $(claude --version 2>&1 | head -1)"
else
  # Sem o CLI, os gates de host NAO rodam — e isso e' amarelo contado, nao verde.
  warn "CLI 'claude' ausente — os gates de host nao vao rodar"
fi
printf '  %sbash: %s%s\n' "$C_DIM" "$(bash --version | head -1 | sed 's/.*version //; s/ .*//')" "$C_OFF"

sec "2 · bit de execucao"
NX="$(find plugins scripts tests -name '*.sh' -not -perm -u+x 2>/dev/null | wc -l | tr -d ' ')"
[ "$NX" = "0" ] && ok "todos os .sh executaveis" || { bad "$NX script(s) sem +x"; find plugins scripts tests -name '*.sh' -not -perm -u+x | sed 's/^/      /' >&2; }

sec "3 · gates de host"
if command -v claude >/dev/null 2>&1; then
  # validate-plugins.sh aplica a allowlist com caducidade; o `validate` cru nao distingue o aviso
  # aceito de proposito do aviso novo, nem percebe quando o aceito deixou de aparecer.
  tiered_check "validate (allowlist com caducidade)" "VALIDATE PASSOU" bash scripts/validate-plugins.sh
  tiered_check "custo always-on (ratchet)" "-" bash scripts/plugin-token-cost.sh
else
  warn "gates de host pulados (sem CLI)"
fi

sec "3b · gates estaticos de componente"
tiered_check "frontmatter"          "FRONTMATTER OK"   bash scripts/validate-frontmatter.sh
tiered_check "orcamento de listagem" "SKILL BUDGET OK" bash scripts/measure-skill-budget.sh
tiered_check "paridade de hosts" "PARIDADE OK" bash scripts/check-host-parity.sh
tiered_check "contagens em prosa"   "conferem com o disco" bash scripts/validate-playbook-counts.sh

sec "4 · suites"
tiered_check "smoke"        "SUITE PASSOU"       bash tests/smoke/run.sh
tiered_check "completeness" "TUDO ENTREGUE"      bash tests/completeness-check.sh
tiered_check "e2e"          "E2E PASSOU"         bash tests/e2e/run.sh
tiered_check "unit"         "Suite unit passou"  bash tests/unit/run.sh
tiered_check "enterprise"   "ENTERPRISE PASSOU"  bash tests/enterprise/run.sh
tiered_check "evals estaticos" "EVALS ESTATICOS OK" bash scripts/validate-evals.sh
tiered_check "docs gerados"    "GERADOS EM DIA"     bash tests/docs-generated-fresh.sh
tiered_check "glossario"       "GLOSSARY CHECK PASSOU"        bash tests/command-glossary-check.sh
tiered_check "politica de idioma" "LANGUAGE POLICY CHECK PASSOU" bash tests/language-policy-check.sh

sec "5 · instalacao a seco"
tiered_check "install --dry-run" "-" bash scripts/install.sh --dry-run --yes --config-dir "$(mktemp -d)"

printf '\n───────────────────────────────\n'
printf '%d ok · %d falha · %d bloqueado\n' "$PASS" "$FAIL" "$BLOCKED"
if [ "$FAIL" -eq 0 ]; then
  rm -rf "$EVID"
  printf 'PILOT CHECK PASSOU\n'
  [ "$BLOCKED" -gt 0 ] && printf '%s(%d check(s) nao puderam rodar — veja acima)%s\n' "$C_WARN" "$BLOCKED" "$C_OFF"
  exit 0
fi
printf 'PILOT CHECK FALHOU · evidencia preservada em %s\n' "$EVID" >&2
exit 1
