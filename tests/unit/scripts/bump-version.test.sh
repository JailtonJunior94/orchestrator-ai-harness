#!/usr/bin/env bash
# tests / unit / scripts / bump-version.test.sh
#
# O TESTE QUE JUSTIFICA O SCRIPT EXISTIR.
#
# Um bump que imprime "✓ arquivo" sem verificar se o arquivo mudou mente por releases inteiras:
# o padrao do sed deixa de casar, o carimbo nao e' aplicado, e o ✓ continua saindo. O caso 3
# abaixo prova que a versao COM o guard falha e a versao SEM o guard passa mentindo — e' o
# "teste de regressao que falha contra o codigo antigo".

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
. "$REPO/tests/unit/lib/assert.sh"

W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
cp -R "$REPO" "$W/repo" 2>/dev/null
rm -rf "$W/repo/.git"
cd "$W/repo"

describe "bump-version — o guard cksum falha alto quando o padrao quebra"

OLD="$(jq -r '.plugins[0].version' .claude-plugin/marketplace.json)"

# 1. bump normal
bash scripts/bump-version.sh 9.9.1 >/dev/null 2>&1
assert_eq "0" "$?" "bump limpo sai 0"
assert_eq "9.9.1" "$(jq -r '.plugins[0].version' .claude-plugin/marketplace.json)" "manifesto carimbado"
assert_eq "9.9.1" "$(jq -r .version plugins/lt/.claude-plugin/plugin.json)" "plugin.json carimbado"
assert_eq "v9.9.1" "$(jq -r '.extraKnownMarketplaces.lt.source.ref' enterprise/managed-settings.json)" "pin do managed carimbado"
assert_contains "$(grep -m1 '^VERSION=' enterprise/bootstrap-mac.sh)" "v9.9.1" "bootstrap carimbado"

# O pin nunca pode virar branch: rollback por re-pin deixa de ser reprodutivel.
assert_eq "false" "$(jq '.extraKnownMarketplaces.lt.source | has("branch")' enterprise/managed-settings.json)" "pin sem branch"

# 2. reexecucao idempotente
bash scripts/bump-version.sh 9.9.1 >/dev/null 2>&1
assert_eq "0" "$?" "reexecutar com a mesma versao sai 0 (idempotente)"

# 3. padrao estrutural quebrado -> TEM de falhar
perl -i -pe 's/^VERSION="v9\.9\.1"/VERSAO_ERRADA="v9.9.1"/' enterprise/bootstrap-mac.sh
bash scripts/bump-version.sh 9.9.2 >/dev/null 2>&1
assert_eq "1" "$?" "padrao quebrado num arquivo estrutural REPROVA o bump"

# 4. a mesma situacao, contra um stamp() sem o ramo de deteccao: passa mentindo.
#    Isto nao testa o produto — testa que o guard e' o que faz a diferenca.
python3 - <<'PYEOF'
import io
s = io.open("scripts/bump-version.sh", encoding="utf-8").read()
start = s.index("  elif grep -qE -- \"$want\" \"$f\"; then")
end = s.index("  fi\n}", start)
ingenuo = s[:start] + "  else\n    printf '  OK %s\\n' \"$f\"\n" + s[end:]
io.open("scripts/bump-ingenuo.sh", "w", encoding="utf-8").write(ingenuo)
PYEOF
chmod +x scripts/bump-ingenuo.sh
bash scripts/bump-ingenuo.sh 9.9.3 >/dev/null 2>&1
assert_eq "0" "$?" "sem o guard, o MESMO padrao quebrado passa com exit 0 (o defeito que o guard evita)"

# 5. prosa que nao menciona a versao nao reprova
printf '# doc sem versao\n' > docs/sem-versao.md
OUT="$(bash scripts/bump-version.sh 9.9.4 2>&1)"
assert_not_contains "$OUT" "docs/sem-versao.md: nenhum carimbo" "prosa sem a versao nao e tratada como padrao quebrado"

# 6. argumento invalido
bash scripts/bump-version.sh "nao-e-semver" >/dev/null 2>&1
assert_eq "2" "$?" "versao fora de semver recusada com exit 2"

end_describe
