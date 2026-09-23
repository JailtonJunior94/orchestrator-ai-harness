#!/usr/bin/env bash
# tests / language-policy-check.sh — banner de sucesso: LANGUAGE POLICY CHECK PASSOU
#
# UMA REGRA, UM DONO. Afirmacao absoluta sobre idioma vive so em tres lugares (ver
# docs/language-policy.md): CLAUDE.md §6, plugins/lt/config/policy-texts.md e a regra
# R-STYLE-001.1 de plugins/lt/config/constitution.md. Copia da regra em outro arquivo diverge na
# primeira edicao, e o agente obedece a copia que leu por ultimo.
#
# O que este teste cobra:
#   1. nenhuma afirmacao absoluta de idioma fora dos donos (.md do repo);
#   2. docs/language-policy.md aponta para os donos e nao legisla por conta propria;
#   3. nomes de skill, command, agent e hook em kebab ASCII; nomes de arquivo ASCII sem espaco;
#   4. tokens do audit trail (vocabulario de approve.sh) em kebab ASCII;
#   5. description em pt-BR — DELEGADO a scripts/validate-frontmatter.sh --language-only, que e'
#      o dono unico da heuristica. Duas copias da heuristica divergiriam como duas copias da regra.
#
# Os padroes de "afirmacao absoluta" estao aqui dentro, entao este arquivo NAO entra na varredura
# (ele so varre .md). E' a mesma licao do smoke: guard textual que carrega os proprios literais
# casa a si mesmo.

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

OWNERS="CLAUDE.md plugins/lt/config/policy-texts.md plugins/lt/config/constitution.md"
KEBAB='^[a-z0-9]+(-[a-z0-9]+)*$'

sec "uma regra, um dono"
# Modificador absoluto seguido, na mesma frase, de um idioma. Janela curta de proposito:
# "sempre ... em ingles" a 40 caracteres e' regra; a 200 caracteres e' coincidencia.
LANG_RE='(sempre|obrigatoriamente|somente|apenas|exclusivamente|nunca)[^.|]{0,40}[[:space:]](em|no idioma)[[:space:]]+(ingl[eê]s|portugu[eê]s|pt-br)([^a-z]|$)'
MUST_RE='(devem?|precisam?|t[eê]m de|tem que)[[:space:]]+(ser|estar)[[:space:]]+(escrit[oa]s?[[:space:]]+)?em[[:space:]]+(ingl[eê]s|portugu[eê]s|pt-br)'
EN_RE='must be (written )?in (english|portuguese)'
HITS=""
while IFS= read -r f; do
  f="${f#./}"
  case " $OWNERS " in *" $f "*) continue ;; esac
  H="$(grep -niE -e "$LANG_RE" -e "$MUST_RE" -e "$EN_RE" "$f" 2>/dev/null | head -3)"
  [ -n "$H" ] && HITS="$HITS
$f: $H"
done <<EOF
$(find . -name '*.md' -not -path './.git/*' -not -path '*/node_modules/*' | sort)
EOF
if [ -n "$HITS" ]; then
  bad "afirmacao absoluta de idioma fora dos donos ($OWNERS) — aponte para o dono em vez de repetir:"
  printf '%s\n' "$HITS" | sed '/^$/d' | cut -c1-160 | sed 's/^/      /' >&2
else
  ok "nenhuma afirmacao absoluta de idioma fora dos donos"
fi

POLICY="docs/language-policy.md"
if [ -r "$POLICY" ]; then
  MISSING_REF=""
  for o in $OWNERS; do grep -q -- "$o" "$POLICY" || MISSING_REF="$MISSING_REF $o"; done
  [ -z "$MISSING_REF" ] && ok "$POLICY aponta para os donos" || bad "$POLICY nao aponta para:$MISSING_REF"
else
  bad "$POLICY ausente"
fi

sec "nomes em kebab ASCII"
NK=""
for d in plugins/lt/skills/*/; do
  n="$(basename "$d")"
  printf '%s' "$n" | grep -qE "$KEBAB" || NK="$NK skill:$n"
done
for f in plugins/lt/commands/*.md plugins/lt/agents/*.md plugins/lt/hooks/*.sh; do
  [ -f "$f" ] || continue
  n="$(basename "$f")"; n="${n%.md}"; n="${n%.sh}"
  printf '%s' "$n" | grep -qE "$KEBAB" || NK="$NK $f"
done
[ -z "$NK" ] && ok "skills, commands, agents e hooks em kebab ASCII" || bad "fora de kebab ASCII:$NK"

# Nome de arquivo com acento ou espaco quebra script de shell sem aspas em algum lugar da
# frota, e o sintoma aparece longe da causa. LC_ALL=C faz o grep ver bytes, nao caracteres.
NA="$(find . -not -path './.git/*' -not -path '*/__pycache__/*' -print 2>/dev/null \
      | LC_ALL=C grep -nE '[^ -~]| ' | head -5)"
[ -z "$NA" ] && ok "todo nome de arquivo e diretorio e' ASCII sem espaco" \
  || { bad "nome de arquivo com caractere nao-ASCII ou espaco:"; printf '%s\n' "$NA" | sed 's/^/      /' >&2; }

sec "tokens do audit trail"
APPROVE="plugins/lt/scripts/approve.sh"
if [ -r "$APPROVE" ]; then
  TOKENS="$(sed -nE 's/^(PHASES|BYPASS|ADHOC)="([^"]*)".*/\2/p' "$APPROVE" | tr ' ' '\n' | sed '/^$/d')"
  if [ -z "$TOKENS" ]; then
    # Vocabulario ilegivel e' falha: o teste nao pode aprovar o que nao conseguiu ler.
    bad "nao consegui ler PHASES/BYPASS/ADHOC de $APPROVE"
  else
    TB="$(printf '%s\n' "$TOKENS" | grep -vE "$KEBAB" | tr '\n' ' ')"
    [ -z "$TB" ] && ok "$(printf '%s\n' "$TOKENS" | wc -l | tr -d ' ') tokens do audit trail em kebab ASCII" \
      || bad "token do audit trail fora de kebab ASCII: $TB"
  fi
else
  bad "$APPROVE ausente"
fi

sec "description em pt-BR (dono: scripts/validate-frontmatter.sh)"
if OUT="$(bash scripts/validate-frontmatter.sh --language-only 2>&1)"; then
  ok "$(printf '%s\n' "$OUT" | tail -1)"
else
  bad "validate-frontmatter --language-only reprovou:"
  printf '%s\n' "$OUT" | grep -E 'FALHA' | head -10 | sed 's/^/      /' >&2
fi

printf '\n───────────────────────────────\n'
printf '%d ok · %d falha\n' "$OK" "$BAD"
if [ "$BAD" -eq 0 ]; then printf 'LANGUAGE POLICY CHECK PASSOU\n'; exit 0; fi
printf 'LANGUAGE POLICY CHECK FALHOU\n' >&2; exit 1
