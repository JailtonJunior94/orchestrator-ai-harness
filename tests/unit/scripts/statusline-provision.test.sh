#!/usr/bin/env bash
# tests / unit / scripts / statusline-provision.test.sh
#
# scripts/lib/provision-statusline.py e' o UNICO caminho pelo qual a barra do harness chega a
# alguem: plugin nenhum entrega statusLine (nao e' campo de plugin.json). Tres promessas dele
# que este teste cobra, cada uma com o custo de quebrar:
#
#   1. statusline de TERCEIRO nunca e' sobrescrita (`skipped-foreign`) — muita gente ja tem barra
#      propria, e apagar a de alguem num install e' motivo de desinstalar o harness;
#   2. o comando aponta para o caminho ESTAVEL (<perfil>/lt/statusline-shim.sh), nunca para o
#      cache versionado, que e' podado a cada update;
#   3. reexecucao sem mudanca devolve `unchanged` e nao reescreve nada.
#
# HOME e CLAUDE_CONFIG_DIR isolados, os dois: o provisionador resolve o perfil por
# CLAUDE_CONFIG_DIR, e isolar so o HOME ja deixou um teste escrever no perfil real.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
. "$REPO/tests/unit/lib/assert.sh"

PROV="$REPO/scripts/lib/provision-statusline.py"
W="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$W"' EXIT
export HOME="$W/home"
export CLAUDE_CONFIG_DIR="$W/home/.claude"
mkdir -p "$CLAUDE_CONFIG_DIR"
SET="$CLAUDE_CONFIG_DIR/settings.json"
SHIM="$CLAUDE_CONFIG_DIR/lt/statusline-shim.sh"

# jget <json> <campo> — le um campo de uma linha JSON sem depender de jq.
jget() { printf '%s' "$1" | python3 -c 'import json,sys; v=json.load(sys.stdin).get(sys.argv[1]); print("" if v is None else v)' "$2"; }
setting() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print((d.get("statusLine") or {}).get("command",""))' "$SET"; }
prov() { python3 "$PROV" --repo "$REPO" "$@"; }

describe "isolamento"
assert_not_scratchpad || { end_describe; exit 1; }

describe "instalacao limpa preserva o resto do settings.json"
printf '{"model":"opus","enabledPlugins":{"outro@x":true}}\n' > "$SET"
OUT="$(prov)"
assert_eq "installed" "$(jget "$OUT" action)" "primeira execucao: installed"
assert_eq "bash \"$SHIM\"" "$(setting)" "comando aponta para o caminho ESTAVEL do perfil isolado"
assert_not_contains "$(setting)" "/plugins/cache/" "nunca aponta para o cache versionado"
[ -x "$SHIM" ] && ok "shim copiado e executavel" || bad "shim ausente ou sem +x em $SHIM"
KEEP="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("model"), d["enabledPlugins"].get("outro@x"))' "$SET")"
assert_eq "opus True" "$KEEP" "chaves de terceiro sobrevivem intactas"

describe "reexecucao e' unchanged"
BEFORE="$(cksum < "$SET")"
OUT="$(prov)"
assert_eq "unchanged" "$(jget "$OUT" action)" "segunda execucao: unchanged"
assert_eq "$BEFORE" "$(cksum < "$SET")" "settings.json nao foi reescrito"

describe "shim divergente e' atualizado"
printf '#!/usr/bin/env bash\necho velho\n' > "$SHIM"
OUT="$(prov)"
assert_eq "updated" "$(jget "$OUT" action)" "shim alterado no perfil: updated"
cmp -s "$SHIM" "$REPO/plugins/lt/statusline/statusline-shim.sh" && ok "shim restaurado da fonte" || bad "shim nao foi restaurado"

describe "forma legada (cache versionado) e' reconhecida como nossa"
python3 - "$SET" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["statusLine"] = {"type": "command", "command": "bash /x/.claude/plugins/cache/lt/lt/0.0.9/statusline/statusline-shim.sh"}
json.dump(d, open(p, "w"))
PY
OUT="$(prov)"
assert_eq "updated" "$(jget "$OUT" action)" "legado migra para o caminho estavel"
assert_eq "bash \"$SHIM\"" "$(setting)" "comando reescrito para a forma estavel"

describe "skipped-foreign: barra de terceiro nunca e' sobrescrita"
rm -f "$SHIM"
printf '{"statusLine":{"type":"command","command":"bash ~/minha-barra.sh"},"model":"opus"}\n' > "$SET"
BEFORE="$(cksum < "$SET")"
bak_sum() { if [ -f "$SET.bak.statusline" ]; then cksum < "$SET.bak.statusline"; else echo none; fi; }
BAK_BEFORE="$(bak_sum)"
OUT="$(prov)"
assert_eq "skipped-foreign" "$(jget "$OUT" action)" "statusline de terceiro: skipped-foreign"
assert_eq "bash ~/minha-barra.sh" "$(jget "$OUT" existing)" "a saida diz qual barra foi preservada"
assert_eq "$BEFORE" "$(cksum < "$SET")" "settings.json byte a byte intacto"
[ ! -e "$SHIM" ] && ok "nenhum shim copiado quando a barra e' de terceiro" || bad "shim copiado mesmo com barra de terceiro"
assert_eq "$BAK_BEFORE" "$(bak_sum)" "nenhum backup novo: nada foi escrito"

describe "dry-run nao escreve nada"
rm -f "$SET" "$SHIM"
OUT="$(prov --dry-run)"
assert_eq "dry-run" "$(jget "$OUT" action)" "action dry-run"
assert_eq "installed" "$(jget "$OUT" would)" "informa o que faria"
[ ! -e "$SET" ] && [ ! -e "$SHIM" ] && ok "nenhum arquivo criado" || bad "dry-run escreveu em disco"

describe "fonte ausente e' erro, nao sucesso"
OUT="$(python3 "$PROV" --repo "$W/nao-existe")"
assert_eq "error" "$(jget "$OUT" action)" "repo sem shim: action error"
[ ! -e "$SET" ] && ok "nada escrito quando a fonte falta" || bad "escreveu settings sem fonte"

end_describe
