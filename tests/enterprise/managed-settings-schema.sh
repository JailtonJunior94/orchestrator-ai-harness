#!/usr/bin/env bash
# tests / enterprise / managed-settings-schema.sh — a forma do payload de politica.

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MS="$REPO/enterprise/managed-settings.json"
OK=0; BAD=0
ok()  { OK=$((OK+1));  printf '  ✓ %s\n' "$1"; }
bad() { BAD=$((BAD+1)); printf '  ✗ %s\n' "$1" >&2; }

printf '\n▸ managed-settings-schema\n'
jq empty "$MS" 2>/dev/null && ok "JSON valido" || bad "JSON invalido"

jq -e '.extraKnownMarketplaces.lt.source.repo == "JailtonJunior94/orchestrator-ai-harness"' "$MS" >/dev/null \
  && ok "repo correto" || bad "repo errado"
jq -r '.extraKnownMarketplaces.lt.source.ref' "$MS" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$' \
  && ok "pin em tag semver" || bad "pin nao e' tag semver"
jq -e '.extraKnownMarketplaces.lt.source | has("branch") | not' "$MS" >/dev/null \
  && ok "sem branch no pin" || bad "pin por branch — rollback deixa de ser reprodutivel"
jq -e '.enabledPlugins["lt@lt"] == true' "$MS" >/dev/null && ok "lt@lt habilitado" || bad "lt@lt nao habilitado"
[ "$(jq '.permissions.deny | length' "$MS")" -ge 20 ] && ok "deny >= 20" || bad "deny < 20"

# CHAVE NAO DOCUMENTADA NAO ENTRA. Governanca sobre chave que pode sumir num upgrade nao e'
# governanca — e' uma aposta que so falha quando mais importa.
jq -e 'has("skillListingBudgetFraction") | not' "$MS" >/dev/null \
  && ok "sem skillListingBudgetFraction (nao documentada)" || bad "usa chave nao documentada"

# defaultMode ausente e' deliberado.
jq -e '.permissions | has("defaultMode") | not' "$MS" >/dev/null \
  && ok "sem defaultMode (nao rebaixa quem usa auto)" || bad "defaultMode sobrescreveria a escolha de cada pessoa"

# Todo MCP da allowlist tem de estar citado na politica escrita — senao a allowlist e o
# documento divergem e ninguem percebe.
POLICY="$REPO/docs/policy/ia-automacao.md"
# Casamento pelo serverName LITERAL, nao por heuristica de vendor: a politica tem de nomear
# o que a allowlist declara, senao "homologado" vira interpretacao.
MISS=""
while IFS= read -r srv; do
  grep -qF -- "\`$srv\`" "$POLICY" 2>/dev/null || MISS="$MISS $srv"
done <<EOF
$(jq -r '.allowedMcpServers[].serverName' "$MS")
EOF
[ -z "$MISS" ] && ok "todo serverName da allowlist esta nomeado na politica" \
  || bad "serverName na allowlist e ausente da politica:$MISS"

# A direcao inversa: servidor na politica e ausente do payload seria homologacao que nao chegou
# a maquina nenhuma.
EXTRA=""
while IFS= read -r srv; do
  jq -e --arg s "$srv" '.allowedMcpServers | map(.serverName) | index($s)' "$MS" >/dev/null 2>&1 \
    || EXTRA="$EXTRA $srv"
done <<EOF
$(grep -oE '^\| [`][a-zA-Z0-9_]+[`]' "$POLICY" | tr -d '|` ' | grep -v '^serverName$')
EOF
[ -z "$EXTRA" ] && ok "todo servidor da politica esta no payload" \
  || bad "homologado na politica e ausente do payload:$EXTRA"

# Descontaminacao do payload. Os padroes vêm de config/forbidden-patterns.txt, nunca embutidos
# aqui: guard textual que carrega os proprios literais casa a si mesmo e reprova o repo inteiro.
# Este erro ja aconteceu tres vezes neste repositorio — no gate de descontaminacao, no de bash
# 3.2, e aqui.
PATFILE="$REPO/config/forbidden-patterns.txt"
if [ -r "$PATFILE" ]; then
  CONTAM=0
  while IFS= read -r pat; do
    case "$pat" in ''|\#*) continue ;; esac
    grep -qiE -- "$pat" "$MS" 2>/dev/null && { bad "payload casa padrao proibido: $pat"; CONTAM=1; }
  done < "$PATFILE"
  [ "$CONTAM" -eq 0 ] && ok "payload sem referencia herdada"
else
  bad "config/forbidden-patterns.txt ausente — a descontaminacao nao pode ser verificada"
fi

printf '  %d ok · %d falha\n' "$OK" "$BAD"
[ "$BAD" -eq 0 ]
