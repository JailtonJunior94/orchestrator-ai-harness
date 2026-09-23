#!/usr/bin/env bash
# orchestrator-ai-harness / enterprise / verify.sh
#
# Confirma que a politica gerenciada esta instalada e coerente com este repositorio.
# Roda depois do bootstrap, e tambem sozinho para auditar uma maquina.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/.." && pwd)"

case "$(uname -s)" in
  Darwin) DEST="/Library/Application Support/ClaudeCode/managed-settings.json" ;;
  Linux)  DEST="/etc/claude-code/managed-settings.json" ;;
  *)      printf 'SO nao suportado por este script: %s\n' "$(uname -s)" >&2; exit 2 ;;
esac
[ -n "${LT_VERIFY_TARGET:-}" ] && DEST="$LT_VERIFY_TARGET"

if [ -t 1 ]; then C_OK=$'\033[32m'; C_BAD=$'\033[31m'; C_OFF=$'\033[0m'
else C_OK=""; C_BAD=""; C_OFF=""; fi
OK=0; BAD=0
ok()  { OK=$((OK+1));  printf '  %s✓%s %s\n' "$C_OK" "$C_OFF" "$1"; }
bad() { BAD=$((BAD+1)); printf '  %s✗%s %s\n' "$C_BAD" "$C_OFF" "$1" >&2; }

printf '\n── verificando a politica gerenciada\n  %s\n\n' "$DEST"

[ -f "$DEST" ] && ok "arquivo presente" || { bad "arquivo AUSENTE"; printf '\nFALHOU\n' >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { printf 'jq necessario\n' >&2; exit 2; }
jq empty "$DEST" 2>/dev/null && ok "JSON valido" || bad "JSON invalido"

WANT="$(jq -r '.plugins[0].version' "$REPO_ROOT/.claude-plugin/marketplace.json" 2>/dev/null)"
PIN="$(jq -r '.extraKnownMarketplaces.lt.source.ref // ""' "$DEST")"
[ "$PIN" = "v$WANT" ] && ok "pin $PIN == versao do manifesto" || bad "pin '$PIN' != v$WANT"

printf '%s' "$PIN" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$' \
  && ok "pin e' tag semver, nao branch" || bad "pin '$PIN' nao e' tag semver"

jq -e '.extraKnownMarketplaces.lt.source | has("branch") | not' "$DEST" >/dev/null \
  && ok "sem 'branch' no pin" || bad "pin usa branch — rollback deixa de ser reprodutivel"

jq -e '.enabledPlugins["lt@lt"] == true' "$DEST" >/dev/null \
  && ok "lt@lt habilitado" || bad "lt@lt nao habilitado"

DENY="$(jq '.permissions.deny | length' "$DEST" 2>/dev/null || echo 0)"
[ "${DENY:-0}" -ge 20 ] && ok "$DENY regras de deny" || bad "so $DENY regras de deny (minimo 20)"

# Chave nao documentada nao entra: governanca sobre chao que some num upgrade nao e' governanca.
jq -e 'has("skillListingBudgetFraction") | not' "$DEST" >/dev/null \
  && ok "sem chave nao documentada (skillListingBudgetFraction)" \
  || bad "usa skillListingBudgetFraction, que nao esta na documentacao oficial"

# defaultMode ausente e' DELIBERADO: managed vence user, e mandar 'default' rebaixaria quem
# escolheu 'auto', em silencio, no primeiro restart.
jq -e '.permissions | has("defaultMode") | not' "$DEST" >/dev/null \
  && ok "permissions.defaultMode ausente (nao rebaixa quem usa auto)" \
  || bad "managed define defaultMode e vai sobrescrever a escolha de cada pessoa"

# Todo plugin do manifesto tem plugin.json coerente.
while IFS= read -r n; do
  PJ="$REPO_ROOT/plugins/$n/.claude-plugin/plugin.json"
  if [ -r "$PJ" ] && jq -e --arg n "$n" '.name == $n and (.version | test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))' "$PJ" >/dev/null; then
    ok "plugin $n com manifesto valido"
  else
    bad "plugin $n sem plugin.json coerente"
  fi
done <<EOF
$(jq -r '.plugins[].name' "$REPO_ROOT/.claude-plugin/marketplace.json")
EOF

printf '\n%d ok · %d falha\n' "$OK" "$BAD"
[ "$BAD" -eq 0 ] && { printf 'VERIFY PASSOU\n'; exit 0; }
printf 'VERIFY FALHOU\n' >&2; exit 1
