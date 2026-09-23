#!/usr/bin/env bash
# tests / unit / scripts / reconcile-idempotent.test.sh
#
# O reconciliador prometia "rodar duas vezes devolve unchanged". O conteudo ja era idempotente
# (uma entrada no registry), mas a segunda rodada relatava "registered" e reescrevia registry e
# settings, trocando o backup. Instalador que sempre diz "registrei" nao deixa ninguem
# distinguir instalacao nova de reexecucao sem efeito.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
. "$REPO/tests/unit/lib/assert.sh"

W="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$W"' EXIT
export HOME="$W" CLAUDE_CONFIG_DIR="$W/.claude"
mkdir -p "$CLAUDE_CONFIG_DIR"
printf '{"theme":"dark","enabledPlugins":{"outro@x":true}}\n' > "$CLAUDE_CONFIG_DIR/settings.json"

describe "isolamento"
assert_not_scratchpad

recon() { python3 "$REPO/scripts/lib/reconcile-plugins.py" --repo "$REPO" --marketplace lt --plugins lt --scope user "$@"; }
sig() { cksum "$CLAUDE_CONFIG_DIR/settings.json" "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json" 2>/dev/null; }

describe "dry-run nao escreve"

recon --dry-run >/dev/null
assert_eq "" "$(ls "$CLAUDE_CONFIG_DIR/plugins" 2>/dev/null)" "nenhum cache nem registry criado"
assert_eq '{"theme":"dark","enabledPlugins":{"outro@x":true}}' "$(tr -d ' \n' < "$CLAUDE_CONFIG_DIR/settings.json")" "settings intocado"

describe "primeira rodada instala, segunda nao faz nada"

FIRST="$(recon)"
assert_contains "$FIRST" '"action": "cache-created"' "primeira rodada cria o cache"
assert_contains "$FIRST" '"action": "registered"' "primeira rodada registra"
BEFORE="$(sig)"
SECOND="$(recon)"
assert_contains "$SECOND" '"action": "cache-ok"' "segunda rodada: cache ok"
assert_contains "$SECOND" '"action": "registry-ok"' "segunda rodada: registry ok, nao registered"
assert_contains "$SECOND" '"action": "already-enabled"' "segunda rodada: settings ja habilitado"
assert_eq "$BEFORE" "$(sig)" "segunda rodada nao reescreve registry nem settings"
assert_contains "$(cat "$CLAUDE_CONFIG_DIR/settings.json")" '"theme": "dark"' "chaves de quem usa sobrevivem"
assert_eq "1" "$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))["plugins"]["lt@lt"]))' "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json")" "uma entrada so' no registry"

end_describe
