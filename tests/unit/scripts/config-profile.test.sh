#!/usr/bin/env bash
# tests / unit / scripts / config-profile.test.sh
#
# O harness precisa instalar no PERFIL certo. Uma maquina pode ter varios
# (~/.claude, ~/.claude-work, ~/.claude-alt), selecionados por CLAUDE_CONFIG_DIR.
#
# Instalar no perfil errado e' a pior classe de erro que existe aqui: nao da mensagem nenhuma,
# o comando diz que funcionou, e o harness simplesmente nao aparece na sessao de quem instalou.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
. "$REPO/tests/unit/lib/assert.sh"

W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
PERFIL_A="$W/perfil-a"; PERFIL_B="$W/perfil-b"
mkdir -p "$PERFIL_A" "$PERFIL_B"
printf '{"model":"opus","theme":"dark"}\n' > "$PERFIL_A/settings.json"
printf '{"model":"sonnet"}\n' > "$PERFIL_B/settings.json"
CK_B="$(cksum < "$PERFIL_B/settings.json")"

describe "resolucao do perfil de configuracao (CLAUDE_CONFIG_DIR)"

CLAUDE_CONFIG_DIR="$PERFIL_A" python3 "$REPO/scripts/lib/reconcile-plugins.py" \
  --repo "$REPO" --marketplace lt --plugins lt >/dev/null 2>&1
assert_eq "0" "$?" "reconciliador roda com perfil explicito"

assert_file_exists "$PERFIL_A/plugins/cache/lt/lt" "cache criado no perfil A"
if [ -d "$PERFIL_B/plugins" ]; then bad "perfil B foi tocado"; else ok "perfil B intocado"; fi
assert_eq "$CK_B" "$(cksum < "$PERFIL_B/settings.json")" "settings do perfil B inalterado"

# Chaves preexistentes do perfil alvo sobrevivem.
MODEL="$(python3 -c "import json;print(json.load(open('$PERFIL_A/settings.json')).get('model'))")"
assert_eq "opus" "$MODEL" "model do perfil A preservado"
THEME="$(python3 -c "import json;print(json.load(open('$PERFIL_A/settings.json')).get('theme'))")"
assert_eq "dark" "$THEME" "theme do perfil A preservado"
EN="$(python3 -c "import json;print(json.load(open('$PERFIL_A/settings.json')).get('enabledPlugins',{}).get('lt@lt'))")"
assert_eq "True" "$EN" "lt@lt habilitado no perfil A"

# Statusline vai para o perfil certo, com caminho ABSOLUTO (nao $HOME, que resolveria errado).
OUT="$(CLAUDE_CONFIG_DIR="$PERFIL_A" python3 "$REPO/scripts/lib/provision-statusline.py" --repo "$REPO" 2>&1)"
assert_contains "$OUT" "perfil-a" "shim provisionado dentro do perfil A"
assert_not_contains "$OUT" '$HOME' "comando usa caminho absoluto, nao \$HOME"
if [ -f "$PERFIL_B/lt/statusline-shim.sh" ]; then bad "shim vazou para o perfil B"; else ok "perfil B sem shim"; fi

end_describe
