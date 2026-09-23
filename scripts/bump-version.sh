#!/usr/bin/env bash
# orchestrator-ai-harness / scripts / bump-version.sh
#
# O unico jeito suportado de subir a versao do core.
#
# A ARMADILHA QUE ESTE SCRIPT EXISTE PARA NAO REPETIR
# Um script de bump que imprime "✓ arquivo.md" sem verificar se o arquivo mudou mente por
# releases inteiras: o padrao do sed deixou de casar, o carimbo nao foi aplicado, e o ✓ continuou
# saindo. Aqui TODO passo que afirma ter mudado um arquivo PROVA com cksum, e distingue:
#
#   mudou             -> ✓
#   nao mudou, mas o alvo ja esta la'  -> =   (reexecucao idempotente, tolerada)
#   nao mudou e o alvo NAO esta la'    -> ✗   (o padrao quebrou; FALHA o script)
#
# O QUE ESTE SCRIPT NAO BUMPA, e por que:
#   CHANGELOG.md          manual, na mesma PR — texto de release e' escrito por gente
#   .version raiz         manual, muda quando um plugin entra ou sai do marketplace
#   plugins independentes cada um tem o proprio ciclo
#   docs/analysis/**      sao registros datados; reescreve-los e' falsificar historico

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

if [ -t 1 ]; then C_OK=$'\033[32m'; C_BAD=$'\033[31m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else C_OK=""; C_BAD=""; C_DIM=""; C_OFF=""; fi

NEW="${1:-}"
printf '%s' "$NEW" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' \
  || { printf 'uso: bump-version.sh X.Y.Z\n' >&2; exit 2; }

command -v jq >/dev/null 2>&1 || { printf 'jq e obrigatorio\n' >&2; exit 1; }

MANIFEST=".claude-plugin/marketplace.json"
OLD="$(jq -r '.plugins[] | select(.name=="lt") | .version' "$MANIFEST")"
[ -n "$OLD" ] || { printf 'nao consegui ler a versao atual do manifesto\n' >&2; exit 1; }

if [ "$OLD" = "$NEW" ]; then
  printf '%saviso: ja esta em %s; rodando assim mesmo (idempotente)%s\n' "$C_DIM" "$NEW" "$C_OFF"
fi

# Plugins de cadencia independente nao acompanham o core. Bash 3.2: sem mapfile.
INDEP=""
while IFS= read -r n; do INDEP="$INDEP $n"; done <<EOF
$(jq -r '.plugins[] | select(.cadence == "independent") | .name' "$MANIFEST")
EOF

FAIL=0
printf '\n── bump %s -> %s\n\n' "$OLD" "$NEW"

# stamp <arquivo> <expr-sed> <regex-que-deve-existir-DEPOIS> [modo]
#
# modo "estrutural" (padrao): o carimbo TEM de estar la'. Nao casar e' falha — e' o caso dos
#   bootstraps, onde um VERSION desatualizado faz a maquina baixar a tag errada.
# modo "prosa": o arquivo PODE nao mencionar a versao. Ausencia total e' informativa; o que
#   falha e' encontrar a versao ANTIGA e nao conseguir substituir.
stamp() {
  f="$1"; expr="$2"; want="$3"; mode="${4:-estrutural}"
  if [ ! -f "$f" ]; then
    printf '  %s✗%s %s: arquivo ausente\n' "$C_BAD" "$C_OFF" "$f" >&2; FAIL=1; return
  fi
  before="$(cksum < "$f")"
  sed -i '' -e "$expr" "$f" 2>/dev/null || sed -i -e "$expr" "$f"
  after="$(cksum < "$f")"
  if [ "$before" != "$after" ]; then
    printf '  %s✓%s %s\n' "$C_OK" "$C_OFF" "$f"
  elif grep -qE -- "$want" "$f"; then
    printf '  %s=%s %s (ja em %s)\n' "$C_DIM" "$C_OFF" "$f" "$NEW"
  elif [ "$mode" = "prosa" ]; then
    printf '  %s·%s %s (nao menciona a versao)\n' "$C_DIM" "$C_OFF" "$f"
  else
    # ESTE ramo e' a razao de ser do script. Sem ele, o passo mentiria em silencio.
    printf '  %s✗%s %s: nenhum carimbo casou E o alvo nao esta presente\n' "$C_BAD" "$C_OFF" "$f" >&2
    FAIL=1
  fi
}

# 1. manifesto — so os lockstep
TMP="$(mktemp)"
jq --arg v "$NEW" '.plugins |= map(if .cadence == "independent" then . else .version = $v end)' \
  "$MANIFEST" > "$TMP" && mv "$TMP" "$MANIFEST"
if [ "$(jq -r '.plugins[] | select(.name=="lt") | .version' "$MANIFEST")" = "$NEW" ]; then
  printf '  %s✓%s %s\n' "$C_OK" "$C_OFF" "$MANIFEST"
else
  printf '  %s✗%s %s: versao nao aplicada\n' "$C_BAD" "$C_OFF" "$MANIFEST" >&2; FAIL=1
fi

# 2. plugin.json dos lockstep
for d in plugins/*/; do
  n="$(basename "$d")"
  case " $INDEP " in *" $n "*) printf '  %s·%s %s (independente, pulado)\n' "$C_DIM" "$C_OFF" "$n"; continue ;; esac
  pj="$d.claude-plugin/plugin.json"
  [ -f "$pj" ] || { printf '  %s✗%s %s ausente\n' "$C_BAD" "$C_OFF" "$pj" >&2; FAIL=1; continue; }
  TMP="$(mktemp)"
  jq --arg v "$NEW" '.version = $v' "$pj" > "$TMP" && mv "$TMP" "$pj"
  [ "$(jq -r .version "$pj")" = "$NEW" ] \
    && printf '  %s✓%s %s\n' "$C_OK" "$C_OFF" "$pj" \
    || { printf '  %s✗%s %s\n' "$C_BAD" "$C_OFF" "$pj" >&2; FAIL=1; }
done

# 3. pin do managed-settings — SEMPRE tag, nunca branch.
#    del(.branch) e' incondicional: um pin por branch torna o rollback nao reprodutivel.
MS="enterprise/managed-settings.json"
if [ -f "$MS" ]; then
  TMP="$(mktemp)"
  jq --arg v "v$NEW" '.extraKnownMarketplaces.lt.source |= (del(.branch) | .ref = $v)' "$MS" > "$TMP" && mv "$TMP" "$MS"
  [ "$(jq -r '.extraKnownMarketplaces.lt.source.ref' "$MS")" = "v$NEW" ] \
    && printf '  %s✓%s %s\n' "$C_OK" "$C_OFF" "$MS" \
    || { printf '  %s✗%s %s\n' "$C_BAD" "$C_OFF" "$MS" >&2; FAIL=1; }
fi

# 4. bootstraps
stamp enterprise/bootstrap-mac.sh    "s|^VERSION=\".*\"|VERSION=\"v$NEW\"|"     "^VERSION=\"v$NEW\""
stamp enterprise/bootstrap-linux.sh  "s|^VERSION=\".*\"|VERSION=\"v$NEW\"|"     "^VERSION=\"v$NEW\""
stamp enterprise/bootstrap-windows.ps1 "s|^\\\$Version *= *\".*\"|\$Version = \"v$NEW\"|" "Version = \"v$NEW\""

# 5. prosa com "versao atual" — substituicao EXATA de OLD para NEW.
#    CHANGELOG, RELEASE-NOTES e docs/analysis ficam de fora: sao historico datado.
if [ "$OLD" != "$NEW" ]; then
  for f in README.md docs/host-facts.md; do
    [ -f "$f" ] || continue
    # `\b` NAO existe no sed do BSD (macOS): a expressao nao casa nada e o arquivo fica
    # intocado, em silencio. Substituicao literal funciona nos dois; a versao e' especifica o
    # bastante para nao precisar de fronteira de palavra.
    stamp "$f" "s/$(printf '%s' "$OLD" | sed 's/\./\\./g')/$NEW/g" "$NEW" prosa
  done
fi

# 6. .claude/settings.json — guardado: so reescreve se o pin JA existir la'.
#    Reintroduzir um pin local que nao estava la' quebra o carregamento do plugin.
SET=".claude/settings.json"
if [ -f "$SET" ] && jq -e '.extraKnownMarketplaces.lt.source' "$SET" >/dev/null 2>&1; then
  TMP="$(mktemp)"
  jq --arg v "v$NEW" '.extraKnownMarketplaces.lt.source |= (del(.branch) | .ref = $v)' "$SET" > "$TMP" && mv "$TMP" "$SET"
  printf '  %s✓%s %s\n' "$C_OK" "$C_OFF" "$SET"
else
  printf '  %s·%s %s (sem pin local — nao reintroduzido de proposito)\n' "$C_DIM" "$C_OFF" "$SET"
fi

printf '\n'
if [ "$FAIL" -ne 0 ]; then
  printf '%sBUMP FALHOU%s — um ou mais carimbos nao casaram. Nada foi commitado.\n' "$C_BAD" "$C_OFF" >&2
  printf 'Corrija o padrao quebrado antes de seguir; um ✓ falso aqui custa uma release.\n' >&2
  exit 1
fi

cat <<EOF
BUMP OK: $OLD -> $NEW

Falta, e e' manual de proposito:
  1. CHANGELOG.md            bloco '## [$NEW] — $(date -u +%Y-%m-%d)' no topo
  2. .version raiz do manifesto, se um plugin entrou ou saiu
  3. varrer resto de prosa:  grep -rn "$OLD" --include='*.md' . | grep -v CHANGELOG
  4. claude plugin tag plugins/lt --dry-run
  5. bash scripts/pilot-check.sh
  6. commit, PR, merge; entao:  git tag -a v$NEW -m "v$NEW" && git push origin v$NEW
     O push da tag e' o deploy.
EOF
