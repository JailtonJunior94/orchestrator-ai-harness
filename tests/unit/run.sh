#!/usr/bin/env bash
# tests / unit / run.sh — descobre e roda todo *.test.sh.
#
# Descoberta por `find`, nunca por lista fixa: lista fixa so valida o que ela mesma lista, e o
# teste novo que ninguem lembrou de registrar fica verde por ausencia.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TOTAL=0; FAILED=0; FILES=""

while IFS= read -r t; do
  TOTAL=$((TOTAL+1))
  printf '\n══ %s\n' "${t#"$HERE/"}"
  if bash "$t"; then :; else FAILED=$((FAILED+1)); FILES="$FILES ${t#"$HERE/"}"; fi
done <<EOF
$(find "$HERE" -name '*.test.sh' -type f | sort)
EOF

printf '\n───────────────────────────────\n'
if [ "$TOTAL" -eq 0 ]; then
  # Zero testes descobertos e' erro, nao sucesso. Suite vazia que imprime verde e' o
  # falso-positivo mais barato que existe.
  printf 'ERRO: nenhum *.test.sh encontrado em %s\n' "$HERE" >&2
  exit 1
fi
if [ "$FAILED" -eq 0 ]; then
  printf 'Suite unit passou (%d arquivos)\n' "$TOTAL"
  exit 0
fi
printf 'Suite unit FALHOU: %d de %d arquivos\n%s\n' "$FAILED" "$TOTAL" "$FILES" >&2
exit 1
