#!/usr/bin/env bash
# tests / command-glossary-check.sh — banner de sucesso: GLOSSARY CHECK PASSOU
#
# docs/command-glossary.md e' a fonte canonica dos nomes `lt:<nome>`. Este teste cobra:
#
#   1. DISCO -> GLOSSARIO: todo command (commands/*.md) e toda skill (skills/*/SKILL.md) tem
#      linha no glossario, com o tipo certo. Nome novo sem linha e' componente que ninguem sabe
#      como chamar.
#   2. GLOSSARIO -> DISCO: toda linha do glossario existe em disco. Linha para nome inexistente
#      e' a classe "prometer o que nao existe" — o agente le, tenta invocar e improvisa.
#   3. SEM BARRA SOLTA: a prosa nunca cita `/<nome>` sem o namespace. No Claude Code a forma
#      sem prefixo nao resolve para o plugin, e o host nao emite erro — a instrucao simplesmente
#      nao faz nada.
#
# A lista de nomes vem do DISCO a cada execucao, nunca de uma lista escrita aqui: lista fixa so
# valida o que ela mesma lista.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
cd "$REPO" || exit 1

if [ -t 1 ]; then C_OK=$'\033[32m'; C_BAD=$'\033[31m'; C_OFF=$'\033[0m'
else C_OK=""; C_BAD=""; C_OFF=""; fi
OK=0; BAD=0
ok()  { OK=$((OK+1));  printf '  %s✓%s %s\n' "$C_OK" "$C_OFF" "$1"; }
bad() { BAD=$((BAD+1)); printf '  %s✗%s %s\n' "$C_BAD" "$C_OFF" "$1" >&2; }
sec() { printf '\n▸ %s\n' "$1"; }

GLOSSARY="docs/command-glossary.md"
PLUGIN="plugins/lt"

if [ ! -r "$GLOSSARY" ]; then
  bad "$GLOSSARY ausente"
  printf '\nGLOSSARY CHECK FALHOU\n' >&2; exit 1
fi

# Disco: "<tipo> <nome>" por linha. bash 3.2: sem array associativo, entao listas em texto.
DISK=""
for f in "$PLUGIN"/commands/*.md; do
  [ -f "$f" ] || continue
  DISK="$DISK
command $(basename "$f" .md)"
done
for f in "$PLUGIN"/skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  DISK="$DISK
skill $(basename "$(dirname "$f")")"
done
DISK="$(printf '%s\n' "$DISK" | sed '/^$/d' | sort -u)"

# Glossario: so linhas de tabela no formato | `lt:<nome>` | <tipo> | ... |
GLOSS="$(sed -nE 's/^\|[[:space:]]*`lt:([a-z0-9][a-z0-9-]*)`[[:space:]]*\|[[:space:]]*(command|skill)[[:space:]]*\|.*/\2 \1/p' "$GLOSSARY" | sort)"

sec "disco -> glossario"
if [ -z "$DISK" ]; then
  # Zero componentes descobertos e' glob quebrado, nao repositorio limpo.
  bad "nenhum command nem skill descoberto em $PLUGIN"
else
  MISSING="$(comm -23 <(printf '%s\n' "$DISK") <(printf '%s\n' "$GLOSS" | sort -u))"
  if [ -n "$MISSING" ]; then
    bad "em disco e sem linha no glossario (ou com tipo errado):"
    printf '%s\n' "$MISSING" | sed 's/^/      /' >&2
  else
    ok "$(printf '%s\n' "$DISK" | wc -l | tr -d ' ') componentes em disco, todos no glossario com o tipo certo"
  fi
fi

sec "glossario -> disco"
EXTRA="$(comm -13 <(printf '%s\n' "$DISK") <(printf '%s\n' "$GLOSS" | sort -u))"
if [ -n "$EXTRA" ]; then
  bad "no glossario e inexistente em disco (ou com tipo errado):"
  printf '%s\n' "$EXTRA" | sed 's/^/      /' >&2
else
  ok "toda linha do glossario resolve em disco"
fi
DUP="$(printf '%s\n' "$GLOSS" | uniq -d)"
[ -z "$DUP" ] && ok "nenhum nome duplicado no glossario" || bad "nome duplicado no glossario: $(printf '%s' "$DUP" | tr '\n' ' ')"

sec "sem barra solta"
NAMES="$(printf '%s\n' "$DISK" | cut -d' ' -f2 | tr '\n' '|' | sed 's/|$//')"
if [ -n "$NAMES" ]; then
  # Barra solta = `/<nome>` no inicio de palavra (depois de espaco, crase, parentese ou aspas).
  # `plugins/lt/skills/review/` nao casa (a barra vem depois de letra), e `/lt:review` tambem nao.
  HITS="$(grep -rnE --binary-files=without-match \
            "(^|[[:space:]\`(\"'])/(${NAMES})([^a-z0-9-]|\$)" \
            --include='*.md' --include='*.sh' --include='*.py' --include='*.json' --include='*.yml' \
            --exclude-dir=.git . 2>/dev/null \
          | grep -v "^./tests/command-glossary-check.sh:" | head -10)"
  if [ -n "$HITS" ]; then
    bad "invocacao sem namespace — use /lt:<nome>:"
    printf '%s\n' "$HITS" | cut -c1-140 | sed 's/^/      /' >&2
  else
    ok "nenhuma invocacao /<nome> sem o namespace lt:"
  fi
fi

printf '\n───────────────────────────────\n'
printf '%d ok · %d falha\n' "$OK" "$BAD"
if [ "$BAD" -eq 0 ]; then printf 'GLOSSARY CHECK PASSOU\n'; exit 0; fi
printf 'GLOSSARY CHECK FALHOU\n' >&2; exit 1
