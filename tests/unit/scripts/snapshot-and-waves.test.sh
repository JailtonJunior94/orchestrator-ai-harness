#!/usr/bin/env bash
# tests / unit / scripts / snapshot-and-waves.test.sh
#
# Dois pedacos do ciclo eram prosa que cada agente reinterpretava:
#
# 1. Como tirar o patch de UMA tarefa sem commit. A receita copiada de shell falhou duas vezes
#    na validacao: `GIT_INDEX_FILE` vazio e' recusado pelo git, e o `rm -rf` da limpeza e'
#    bloqueado pelo proprio hook destrutivo do harness. Agora e' `snapshot` + `task-patch`.
#
# 2. Como compor waves. Com `—` indefinido, a mesma tasks.md dava dois cronogramas; `Com X.Y`
#    era ignorado. Agora e' `waves`, com a regra: `—`/`Não` sozinhas, `Com` so' reciproco.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
. "$REPO/tests/unit/lib/assert.sh"

SDD="$REPO/plugins/lt/lib/sdd.py"
W="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$W"' EXIT
gitc() { git -c commit.gpgsign=false -c user.email=t@t -c user.name=t "$@"; }

describe "snapshot captura a arvore sem tocar indice, ref nem commit"

mkdir -p "$W/r" && ( cd "$W/r" && git init -q && printf 'a\n' > f && git add f && gitc commit -qm i )
HEAD0="$(git -C "$W/r" rev-parse HEAD)"
B="$( cd "$W/r" && python3 "$SDD" snapshot )"
printf 'b\n' >> "$W/r/f"; printf 'novo\n' > "$W/r/novo.txt"
mkdir -p "$W/r/.lt/specs/prd-x" && printf 'relatorio\n' > "$W/r/.lt/specs/prd-x/r.md"
A="$( cd "$W/r" && python3 "$SDD" snapshot )"
assert_ne "$B" "$A" "snapshots antes e depois diferem"
assert_eq "$HEAD0" "$(git -C "$W/r" rev-parse HEAD)" "nenhum commit criado"
assert_eq "" "$(git -C "$W/r" diff --cached --name-only)" "indice real intocado"
assert_contains "$(git -C "$W/r" status --short)" "?? novo.txt" "nao rastreado continua nao rastreado"

SHA="$( cd "$W/r" && python3 "$SDD" task-patch "$B" "$A" evid/1.0.patch --exclude .lt/specs/prd-x )"
assert_eq "$(shasum -a 256 "$W/r/evid/1.0.patch" | cut -d' ' -f1)" "$SHA" "task-patch imprime o sha256 do arquivo gravado"
assert_contains "$(cat "$W/r/evid/1.0.patch")" "novo.txt" "o patch inclui arquivo novo"
assert_not_contains "$(cat "$W/r/evid/1.0.patch")" "relatorio" "o --exclude tira o bundle do patch"
rev_rc() { git -C "$W/r" apply --reverse --check "$W/r/evid/1.0.patch"; }
assert_exit_code 0 rev_rc

describe "waves: — e Não sozinhas, Com so' reciproco, menor id primeiro"

mkdir -p "$W/p/.lt/specs/prd-x" && ( cd "$W/p" && git init -q )
cat > "$W/p/.lt/specs/prd-x/tasks.md" <<'EOF'
| # | Título | Status | Dependências | Paralelizável | Skills |
|---|---|---|---|---|---|
| 1.0 | a | done | — | Não | — |
| 2.0 | b | pending | 1.0 | — | — |
| 3.0 | c | pending | 1.0 | Com 4.0 | — |
| 4.0 | d | pending | 1.0 | Com 3.0 | — |
| 5.0 | e | pending | 1.0 | Com 6.0 | — |
| 6.0 | f | pending | 1.0 | — | — |
| 7.0 | g | pending | 6.0, outro/1.0 | Não | — |
EOF
OUT="$( cd "$W/p" && python3 "$SDD" waves .lt/specs/prd-x )"
assert_contains "$OUT" "wave 1: 2.0" "— roda sozinha e o menor id vai primeiro"
assert_contains "$OUT" "wave 2: 3.0, 4.0" "Com reciproco vira uma wave"
assert_contains "$OUT" "wave 3: 5.0" "Com sem reciproca nao arrasta a outra tarefa"
assert_contains "$OUT" "wave 4: 6.0" "a tarefa que nao declarou roda sozinha"
assert_contains "$OUT" "bloqueada: 7.0" "dependencia externa nao resolvida bloqueia"
assert_contains "$OUT" "outro nao encontrado" "a razao do bloqueio e' dita"
NEXT="$( cd "$W/p" && python3 "$SDD" waves .lt/specs/prd-x --next )"
assert_eq "2.0" "$NEXT" "--next devolve so' a proxima wave"

sed -i '' -e 's/^| 2.0 | b | pending/| 2.0 | b | failed/' "$W/p/.lt/specs/prd-x/tasks.md" 2>/dev/null \
  || sed -i -e 's/^| 2.0 | b | pending/| 2.0 | b | failed/' "$W/p/.lt/specs/prd-x/tasks.md"
assert_contains "$( cd "$W/p" && python3 "$SDD" waves .lt/specs/prd-x )" "wave 1: 3.0, 4.0" "tarefa failed sai do plano sem travar as independentes"

end_describe
