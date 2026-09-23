#!/usr/bin/env bash
# tests / unit / scripts / sdd-anchoring.test.sh
#
# Invariante I-5: a spec pertence ao repositorio onde o comando roda.
# Estes casos existem porque o erro que eles previnem so apareceria meses depois, na forma de
# rastreabilidade RF -> codigo que nao fecha.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
. "$REPO/tests/unit/lib/assert.sh"

SDD="$REPO/plugins/lt/lib/sdd.py"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT

mkdir -p "$W/repo-a/src/deep" "$W/repo-b"
( cd "$W/repo-a" && git init -q ) ; ( cd "$W/repo-b" && git init -q )

describe "I-5 — ancoragem do .lt/specs no repo do cwd"

A_ROOT="$(cd "$W/repo-a" && env -u CLAUDE_PROJECT_DIR -u LT_PROJECT_DIR python3 "$SDD" specs-root)"
B_ROOT="$(cd "$W/repo-b" && env -u CLAUDE_PROJECT_DIR -u LT_PROJECT_DIR python3 "$SDD" specs-root)"
assert_ne "$A_ROOT" "$B_ROOT" "repos diferentes tem raizes de spec diferentes"
assert_contains "$A_ROOT" "repo-a/.lt/specs" "repo-a ancora em si mesmo"
assert_contains "$B_ROOT" "repo-b/.lt/specs" "repo-b ancora em si mesmo"

DEEP="$(cd "$W/repo-a/src/deep" && env -u CLAUDE_PROJECT_DIR -u LT_PROJECT_DIR python3 "$SDD" specs-root)"
assert_eq "$A_ROOT" "$DEEP" "subdiretorio resolve para a RAIZ do repo, nao para o cwd"

# Spec do repo A nao pode ser operada de dentro do repo B.
P="$W/repo-a/.lt/specs/prd-x"; mkdir -p "$P"; printf '# PRD\n' > "$P/prd.md"
( cd "$W/repo-a" && env -u CLAUDE_PROJECT_DIR -u LT_PROJECT_DIR python3 "$SDD" approve "$P" prd ) >/dev/null 2>&1
assert_eq "0" "$?" "aprovar a spec do repo-a de dentro do repo-a funciona"

( cd "$W/repo-b" && env -u CLAUDE_PROJECT_DIR -u LT_PROJECT_DIR python3 "$SDD" state "$P" ) >/dev/null 2>&1
assert_eq "3" "$?" "operar a spec do repo-a de dentro do repo-b e' RECUSADO (exit 3)"

# Alvos perigosos.
( cd "$W/repo-b" && env -u CLAUDE_PROJECT_DIR -u LT_PROJECT_DIR python3 "$SDD" state "$HOME" ) >/dev/null 2>&1
assert_eq "3" "$?" "HOME e' recusado"
( cd "$W/repo-b" && env -u CLAUDE_PROJECT_DIR -u LT_PROJECT_DIR python3 "$SDD" state / ) >/dev/null 2>&1
assert_eq "3" "$?" "raiz do sistema e' recusada"

# Escape hatch explicito.
FORCED="$(cd "$W/repo-a" && env -u CLAUDE_PROJECT_DIR LT_PROJECT_DIR="$W/repo-b" python3 "$SDD" specs-root)"
assert_eq "$B_ROOT" "$FORCED" "LT_PROJECT_DIR sobrepoe a deteccao"

# Repo que ja usa .specs/ mantem a propria convencao: o harness detecta, nao impoe.
mkdir -p "$W/repo-legado/.specs/prd-antigo"
( cd "$W/repo-legado" && git init -q )
LEG="$(cd "$W/repo-legado" && env -u CLAUDE_PROJECT_DIR -u LT_PROJECT_DIR python3 "$SDD" specs-root)"
assert_contains "$LEG" "repo-legado/.specs" "repo com .specs/ existente mantem .specs/"
assert_not_contains "$LEG" ".lt/specs" "nao cria um segundo diretorio de specs"

# Pasta sem git nenhum continua funcionando, ancorada no cwd.
mkdir -p "$W/sem-git/a/b"
NOGIT="$(cd "$W/sem-git/a/b" && env -u CLAUDE_PROJECT_DIR -u LT_PROJECT_DIR python3 "$SDD" specs-root)"
assert_contains "$NOGIT" "sem-git/a/b/.lt/specs" "fora de git ancora no cwd"

# Override explicito de nome de diretorio.
OVR="$(cd "$W/repo-a" && env -u CLAUDE_PROJECT_DIR -u LT_PROJECT_DIR LT_TASKS_ROOT=docs/specs python3 "$SDD" specs-root)"
assert_contains "$OVR" "repo-a/docs/specs" "LT_TASKS_ROOT sobrepoe o nome do diretorio"

# --slug normaliza e --create cria dentro do repo certo.
SLUG="$(cd "$W/repo-a/src/deep" && env -u CLAUDE_PROJECT_DIR -u LT_PROJECT_DIR python3 "$SDD" specs-root --slug "Alarmes Logicos v2" --create)"
assert_contains "$SLUG" "repo-a/.lt/specs/prd-alarmes-logicos-v2" "slug normalizado e ancorado na raiz do repo"
assert_file_exists "$SLUG" "--create criou a arvore"

end_describe
