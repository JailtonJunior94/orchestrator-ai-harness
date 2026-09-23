#!/usr/bin/env bash
# tests / unit / scripts / drift-honest-report.test.sh
#
# `check-spec-drift` pula artefato ausente — o que esta certo, nao da' para conferir a ancora de
# algo que ainda nao existe. O que estava errado era a mensagem: com so' `prd.md` no diretorio,
# ele imprimia "a cadeia PRD -> TechSpec -> Tasks esta integra". Verde por ausencia, na saida do
# gate que existe justamente para nao produzir verde por ausencia.
#
# E `invalidate --from prd` fazia `setdefault` nos descendentes, criando `"tasks": {}` no estado
# de um bundle que nunca teve tasks.md — o estado passava a afirmar conhecer um artefato que
# ninguem escreveu.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
. "$REPO/tests/unit/lib/assert.sh"

SDD="$REPO/plugins/lt/lib/sdd.py"
W="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$W"' EXIT

mk_bundle() {
  mkdir -p "$W/$1/.lt/specs/prd-x"
  ( cd "$W/$1" && git init -q )
  printf '# PRD\n\n- RF-01: algo\n' > "$W/$1/.lt/specs/prd-x/prd.md"
}
drift() { ( cd "$W/$1" && python3 "$SDD" check-spec-drift .lt/specs/prd-x 2>&1 ); }

describe "check-spec-drift nao afirma elo que nao verificou"

mk_bundle solo
OUT="$(drift solo)"
assert_not_contains "$OUT" "esta integra" "nao afirma cadeia integra com so' prd.md"
assert_contains "$OUT" "NAO foram verificados" "diz explicitamente o que nao verificou"
assert_contains "$OUT" "techspec.md" "nomeia o artefato ausente"
assert_contains "$OUT" "tasks.md" "nomeia o segundo artefato ausente"

mk_bundle comts
PRD_HASH="$( cd "$W/comts" && python3 "$SDD" hash .lt/specs/prd-x/prd.md )"
printf '<!-- spec-hash-prd: %s -->\n\n# TechSpec\n' "$PRD_HASH" > "$W/comts/.lt/specs/prd-x/techspec.md"
OUT="$(drift comts)"
assert_contains "$OUT" "PRD -> TechSpec" "nomeia o elo que verificou"
assert_contains "$OUT" "tasks.md" "ainda aponta o que falta"
drift_rc() { ( cd "$W/comts" && python3 "$SDD" check-spec-drift .lt/specs/prd-x ); }
assert_exit_code 0 drift_rc

printf '<!-- spec-hash-prd: %s -->\n\n# TechSpec\n' \
  "0000000000000000000000000000000000000000000000000000000000000001" \
  > "$W/comts/.lt/specs/prd-x/techspec.md"
# Drift real continua reprovando: a mensagem mais honesta nao pode ter afrouxado o gate.
assert_exit_code 1 drift_rc

describe "invalidate nao inventa artefato"

mk_bundle inv
( cd "$W/inv" && python3 "$SDD" approve .lt/specs/prd-x prd >/dev/null 2>&1 )
( cd "$W/inv" && python3 "$SDD" invalidate .lt/specs/prd-x --from prd >/dev/null 2>&1 )
KEYS="$(python3 -c "
import json
print(','.join(sorted(json.load(open('$W/inv/.lt/specs/prd-x/sdd-state.json'))['artifacts'])))
")"
assert_eq "$KEYS" "prd" "estado guarda so' o artefato que existe"


describe "bundle inexistente e' erro limpo, nao traceback"

# `load_state` devolvia o default para diretorio ausente, o comando seguia, e `save_state`
# estourava com traceback do Python num caminho `.../sdd-state.json.tmp`. O operador via um
# stack trace em vez de "o bundle nao existe" — e a causa real (spec apagada por um reset de
# worktree, porque o bundle nunca foi commitado) ficava escondida atras do erro errado.
mkdir -p "$W/vazio" && ( cd "$W/vazio" && git init -q )

# Cada subcomando tem a sua assinatura; o que se afirma e' a mensagem, nao a forma do argumento.
probe() {
  case "$1" in
    invalidate) ( cd "$W/vazio" && python3 "$SDD" invalidate .lt/specs/prd-nao-existe --from prd 2>&1 ) ;;
    approve)    ( cd "$W/vazio" && python3 "$SDD" approve    .lt/specs/prd-nao-existe prd        2>&1 ) ;;
    state)      ( cd "$W/vazio" && python3 "$SDD" state      .lt/specs/prd-nao-existe            2>&1 ) ;;
  esac
}

for cmd in invalidate approve state; do
  OUT="$(probe "$cmd")"
  # A invariante e' dupla: nada de traceback, e a mensagem nomeia o caminho que falta — sem
  # isso o operador nao descobre que a spec foi apagada, so' que "algo deu errado".
  if printf '%s' "$OUT" | grep -q 'Traceback'; then
    bad "$cmd: traceback cru para bundle inexistente"
  elif printf '%s' "$OUT" | grep -q 'prd-nao-existe'; then
    ok "$cmd: erro limpo nomeando o caminho ausente"
  else
    bad "$cmd: mensagem nao nomeia o caminho — $(printf '%s' "$OUT" | head -1)"
  fi
done

end_describe
