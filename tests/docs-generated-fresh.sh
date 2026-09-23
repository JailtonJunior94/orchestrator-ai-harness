#!/usr/bin/env bash
# tests / docs-generated-fresh.sh — banner: GERADOS EM DIA
#
# Prosa gerada que envelhece em silencio e' o defeito que a propria secao de estado do guia
# denuncia. Este gate reexecuta cada gerador e compara com o bloco commitado.
#
# A data e' ignorada na comparacao: ela muda todo dia e faria o gate falhar sozinho. O que
# importa sao os NUMEROS que a secao afirma.

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

if [ -t 1 ]; then C_OK=$'\033[32m'; C_BAD=$'\033[31m'; C_OFF=$'\033[0m'
else C_OK=""; C_BAD=""; C_OFF=""; fi
OK=0; BAD=0
ok()  { OK=$((OK+1));  printf '  %s✓%s %s\n' "$C_OK" "$C_OFF" "$1"; }
bad() { BAD=$((BAD+1)); printf '  %s✗%s %s\n' "$C_BAD" "$C_OFF" "$1" >&2; }

printf '\n▸ blocos gerados\n'

if python3 scripts/lib/inject-generated.py \
     --file docs/REPLICATION-GUIDE.md --id estado \
     --generator scripts/gen-drift-report.sh --check >/dev/null 2>&1; then
  ok "docs/REPLICATION-GUIDE.md §18 reflete o disco"
else
  bad "docs/REPLICATION-GUIDE.md §18 desatualizado"
  printf '     Rode: python3 scripts/lib/inject-generated.py --file docs/REPLICATION-GUIDE.md --id estado --generator scripts/gen-drift-report.sh\n' >&2
fi

# Contagem em prosa sem teste que a cruze com o disco envelhece em silencio. O guia e' o arquivo
# que mais mente quando a forma muda, entao ele e' verificado explicitamente.
printf '\n▸ contagens do guia contra o disco\n'
SK_DISCO=$(ls -1d plugins/lt/skills/*/ | wc -l | tr -d ' ')
HK_DISCO=$(ls -1 plugins/lt/hooks/*.sh | wc -l | tr -d ' ')
SK_GUIA=$(sed -n 's/^| skills | \([0-9]*\) |$/\1/p' docs/REPLICATION-GUIDE.md | head -1)
HK_GUIA=$(sed -n 's/^| hooks registrados | \([0-9]*\) |$/\1/p' docs/REPLICATION-GUIDE.md | head -1)
[ "$SK_GUIA" = "$SK_DISCO" ] && ok "skills: guia $SK_GUIA == disco $SK_DISCO" || bad "skills: guia $SK_GUIA != disco $SK_DISCO"
[ "$HK_GUIA" = "$HK_DISCO" ] && ok "hooks: guia $HK_GUIA == disco $HK_DISCO" || bad "hooks: guia $HK_GUIA != disco $HK_DISCO"

# Todo arquivo citado como ponteiro no guia tem de existir.
# README e CLAUDE.md entram junto com o guia: o README apontou por semanas para um
# docs/VERSIONING.md que nunca existiu, e so' o guia era conferido.
printf '\n▸ ponteiros do guia, do README e do CLAUDE.md\n'
MISS=""
for f in $(grep -ohE '`(scripts|plugins|tests|enterprise|config|docs|\.github)/[A-Za-z0-9_./-]+`' docs/REPLICATION-GUIDE.md README.md CLAUDE.md \
           | tr -d '`' | sort -u); do
  case "$f" in */) continue ;; esac
  [ -e "$f" ] || MISS="$MISS $f"
done
[ -z "$MISS" ] && ok "todo caminho citado existe em disco" || bad "citados e inexistentes:$MISS"

printf '\n▸ contagens em prosa\n'
if COUNTS="$(bash scripts/validate-playbook-counts.sh 2>&1)"; then ok "$COUNTS"; else bad "$COUNTS"; fi

printf '\n%d ok · %d falha\n' "$OK" "$BAD"
[ "$BAD" -eq 0 ] && { printf 'GERADOS EM DIA\n'; exit 0; }
printf 'GERADOS DESATUALIZADOS\n' >&2; exit 1
