#!/usr/bin/env bash
# orchestrator-ai-harness / enterprise / bootstrap-linux.sh
#
# Instala a politica gerenciada da organizacao nesta maquina (Linux e WSL).
#
# CAMINHO OFICIAL, conferido na documentacao:
#   macOS        /Library/Application Support/ClaudeCode/managed-settings.json
#   Linux/WSL    /etc/claude-code/managed-settings.json
#   Windows      C:\Program Files\ClaudeCode\   <- NAO e' ProgramData; ver bootstrap-windows.ps1
#
# LT_DRYRUN=1 usa o arquivo local e pula sudo e verify — e' o que o CI exercita.

set -euo pipefail

VERSION="v0.1.0"
REPO="JailtonJunior94/orchestrator-ai-harness"
DEST="/etc/claude-code/managed-settings.json"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -t lt-managed)"
trap 'rm -f "$TMP"' EXIT

if [ "${LT_DRYRUN:-0}" = "1" ]; then
  cp "$HERE/managed-settings.json" "$TMP"
else
  command -v gh >/dev/null 2>&1 || { printf 'gh ausente — o repositorio e privado\n' >&2; exit 1; }
  command -v jq >/dev/null 2>&1 || { printf 'jq ausente\n' >&2; exit 1; }
  gh auth status >/dev/null 2>&1 || { printf 'gh nao autenticado: rode `gh auth login`\n' >&2; exit 1; }

  # CONFIRMA QUE A TAG EXISTE ANTES DE BAIXAR.
  # Sem esta checagem, um 404 segue pelo pipe e o erro visivel vem do base64
  # ("error decoding base64 input stream") — que nao aponta para a causa nenhuma.
  gh api "repos/$REPO/git/ref/tags/$VERSION" >/dev/null 2>&1 \
    || { printf 'tag %s nao existe em %s\n' "$VERSION" "$REPO" >&2; exit 1; }

  gh api "repos/$REPO/contents/enterprise/managed-settings.json?ref=$VERSION" --jq '.content' \
    | base64 -d > "$TMP"
fi

jq empty "$TMP" || { printf 'JSON invalido\n' >&2; exit 1; }
jq -e --arg v "$VERSION" '.extraKnownMarketplaces.lt.source.ref == $v' "$TMP" >/dev/null \
  || { printf 'o pin do arquivo nao e %s\n' "$VERSION" >&2; exit 1; }

if [ "${LT_DRYRUN:-0}" = "1" ]; then
  printf '[dry-run] payload validado; sudo e verify pulados\n'
  exit 0
fi

sudo mkdir -p "$(dirname "$DEST")"
sudo cp "$TMP" "$DEST"
sudo chmod 644 "$DEST"
bash "$HERE/verify.sh"

cat <<'EOF'

ATENCAO — o passo que todo mundo esquece:

  `enabledPlugins` no managed-settings NAO materializa o cache do plugin.
  Voce reinicia, nao tem harness nenhum, e nao aparece erro.

Rode agora:

    claude plugin install lt@lt
    # ou, a partir do clone do harness:
    bash scripts/install.sh

EOF
