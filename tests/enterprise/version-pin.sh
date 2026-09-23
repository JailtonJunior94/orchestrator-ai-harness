#!/usr/bin/env bash
# tests / enterprise / version-pin.sh — o pin tem de bater em TODO lugar que o carrega.
#
# Uma versao dessincronizada aqui nao da erro: o bootstrap instala, o verify de outra maquina
# passa, e duas maquinas rodam versoes diferentes acreditando estar iguais.

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OK=0; BAD=0
ok()  { OK=$((OK+1));  printf '  ✓ %s\n' "$1"; }
bad() { BAD=$((BAD+1)); printf '  ✗ %s\n' "$1" >&2; }

CORE="$(jq -r '.plugins[] | select(.name=="lt") | .version' "$REPO/.claude-plugin/marketplace.json")"
TAG="v$CORE"
printf '\n▸ version-pin (core %s)\n' "$CORE"

PJ="$(jq -r .version "$REPO/plugins/lt/.claude-plugin/plugin.json")"
[ "$PJ" = "$CORE" ] && ok "plugin.json == manifesto" || bad "plugin.json=$PJ manifesto=$CORE"

MS="$(jq -r '.extraKnownMarketplaces.lt.source.ref' "$REPO/enterprise/managed-settings.json")"
[ "$MS" = "$TAG" ] && ok "managed-settings pin == $TAG" || bad "managed-settings pin=$MS"

for f in bootstrap-mac.sh bootstrap-linux.sh; do
  V="$(grep -m1 '^VERSION=' "$REPO/enterprise/$f" | sed 's/.*"\(.*\)"/\1/')"
  [ "$V" = "$TAG" ] && ok "$f VERSION == $TAG" || bad "$f VERSION=$V"
done
V="$(grep -m1 '^\$Version' "$REPO/enterprise/bootstrap-windows.ps1" | sed 's/.*"\(.*\)"/\1/')"
[ "$V" = "$TAG" ] && ok "bootstrap-windows.ps1 \$Version == $TAG" || bad "windows \$Version=$V"

# Lockstep: todo plugin que nao for `independent` acompanha o core.
while IFS= read -r line; do
  n="$(printf '%s' "$line" | jq -r .name)"
  v="$(printf '%s' "$line" | jq -r .version)"
  c="$(printf '%s' "$line" | jq -r '.cadence // "lockstep"')"
  if [ "$c" = "independent" ]; then
    ok "$n em cadencia independente ($v)"
  elif [ "$v" = "$CORE" ]; then
    ok "$n em lockstep com o core"
  else
    bad "$n declara lockstep mas esta em $v"
  fi
done <<EOF
$(jq -c '.plugins[]' "$REPO/.claude-plugin/marketplace.json")
EOF

printf '  %d ok · %d falha\n' "$OK" "$BAD"
[ "$BAD" -eq 0 ]
