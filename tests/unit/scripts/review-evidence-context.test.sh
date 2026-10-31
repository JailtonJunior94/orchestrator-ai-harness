#!/usr/bin/env bash
# tests / unit / scripts / review-evidence-context.test.sh
#
# O relatorio de review passou a declarar em qual contexto a revisao rodou (I-3 da
# constitution): `- Contexto: fresh | same-thread`. O validador exige a LINHA, nunca o valor —
# falhar pelo valor empurraria o agente a escrever `fresh` sem ser.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=../lib/assert.sh
. "$REPO/tests/unit/lib/assert.sh"

export HOME="$(mktemp -d)"
export CLAUDE_CONFIG_DIR="$HOME/.claude"
V="$REPO/plugins/lt/scripts/validate-review-evidence.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP" "$HOME"' EXIT

describe "validate-review-evidence.sh — linha de contexto da revisao"
assert_not_scratchpad

cat > "$TMP/task-1.0.md" <<'TASK'
# Task 1.0
## Critérios de Aceite
- divisão por zero devolve erro
TASK

write_report() {
  # $1 = linha de contexto (vazia = omitida)
  {
    printf '# Relatório de Review\n\n'
    printf -- '- Veredito: APPROVED_WITH_REMARKS\n'
    [ -n "$1" ] && printf -- '- %s\n' "$1"
    printf -- '- Alvo revisado: diff\n'
    printf -- '- Task file: task-1.0.md\n\n'
    printf '## Mapa de Critérios de Aceite\n'
    printf -- '- [atendido] divisão por zero devolve erro -> calc/media.go:12\n\n'
    printf '## Achados\n- Severidade: low\n- Arquivo: calc/media.go\n- Linha: 12\n- Impacto: nome\n- Dica de correção: renomear\n\n'
    printf '## Arquivos Revisados\n- calc/media.go\n\n'
    printf '## Riscos Residuais\n- nenhum\n\n'
    printf '## Validações Executadas\n- go test ./calc -> PASS\n'
  } > "$TMP/review.md"
}

write_report "Contexto: fresh"
assert_exit_code 0 bash "$V" "$TMP/review.md"

write_report "Contexto: same-thread"
assert_exit_code 0 bash "$V" "$TMP/review.md"

write_report ""
out="$(bash "$V" "$TMP/review.md" 2>&1)"; rc=$?
assert_eq "1" "$rc" "relatorio sem a linha de contexto reprova"
assert_contains "$out" "Contexto: fresh | same-thread" "a mensagem diz qual linha falta"

# Valor fora do vocabulario tambem reprova: a linha existe para ser lida por maquina.
write_report "Contexto: independente"
assert_exit_code 1 bash "$V" "$TMP/review.md"

end_describe
