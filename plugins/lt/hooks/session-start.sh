#!/usr/bin/env bash
# lt / hooks / session-start.sh
# Categoria: CONTEXTO
#
# Injeta contexto no inicio da sessao. exit 0 SEMPRE — um hook de contexto que falha a sessao
# transforma um detalhe cosmetico em impedimento de trabalho.
#
# PREFERENCIAS SAO INJETADAS POR ENUM, NUNCA ECOANDO O ARQUIVO.
# O valor de .lt/preferences.json e' usado como CHAVE para um texto canonico de
# config/policy-texts.md. Sem essa indirecao, qualquer repositorio de terceiro que a pessoa
# abrisse poderia escrever instrucoes nesse arquivo e elas entrariam no system prompt.

set -uo pipefail
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Perfil de configuracao do Claude Code. Esta maquina pode ter varios (~/.claude,
# ~/.claude-work, ~/.claude-alt), selecionados por CLAUDE_CONFIG_DIR — e instalar no
# perfil errado significa que o harness simplesmente nao aparece na sessao de quem o instalou.
LT_CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
LT_PLUGIN_ROOT="$PLUGIN_ROOT"
. "$PLUGIN_ROOT/lib/hook-common.sh" 2>/dev/null || true

PROJECT="${CLAUDE_PROJECT_DIR:-.}"
CTX=""

VERSION="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$PLUGIN_ROOT/.claude-plugin/plugin.json" 2>/dev/null | head -1)"
CTX="Harness LT ${VERSION:-?} ativo."

# --- Preferencias por enum -------------------------------------------------------------------
read_pref() {  # $1=chave
  for f in "$PROJECT/.lt/preferences.json" "$LT_CFG/lt/preferences.json" "$PLUGIN_ROOT/config/preferences.defaults.json"; do
    [ -r "$f" ] || continue
    v="$(sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\\([a-zA-Z0-9_-]*\\)\".*/\\1/p" "$f" | head -1)"
    [ -n "$v" ] && { printf '%s' "$v"; return 0; }
  done
  return 1
}

emit_pref_text() {  # $1=chave  $2=valor
  # So o TEXTO do plugin entra no contexto. O valor do arquivo apenas seleciona qual.
  awk -v k="### $1=$2" '
    $0 == k { on = 1; next }
    on && /^###/ { exit }
    on && /^---/ { exit }
    on && NF { print }
  ' "$PLUGIN_ROOT/config/policy-texts.md" 2>/dev/null | head -4
}

for key in output_language code_comments coauthor_trailer; do
  val="$(read_pref "$key")" || continue
  txt="$(emit_pref_text "$key" "$val")"
  if [ -n "$txt" ]; then
    CTX="$CTX
$txt"
  else
    # Valor fora da enum: cai no default e ANUNCIA. Silencio aqui esconderia um preferences.json
    # adulterado.
    printf '[lt] lt_pref_unknown_enum: %s=%s nao tem texto canonico; usando o default.\n' "$key" "$val" >&2
  fi
done

# --- Spec ativa ------------------------------------------------------------------------------
if [ -d "$PROJECT/.lt/specs" ]; then
  ACTIVE="$(ls -1d "$PROJECT"/.lt/specs/prd-*/ 2>/dev/null | head -1)"
  [ -n "$ACTIVE" ] && CTX="$CTX
Spec ativa: $(basename "$ACTIVE")."
fi

# --- Aviso de atualizacao pendente -----------------------------------------------------------
# Compara a versao ativa no cache com a do clone do marketplace, quando ambos existem.
MKT_MANIFEST="$PROJECT/.claude-plugin/marketplace.json"
if [ -r "$MKT_MANIFEST" ] && [ -n "$VERSION" ]; then
  LATEST="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$MKT_MANIFEST" | head -2 | tail -1)"
  if [ -n "$LATEST" ] && [ "$LATEST" != "$VERSION" ]; then
    CTX="$CTX
Atualizacao pendente: rodando $VERSION, disponivel $LATEST. Rode \`bash scripts/update.sh\`."
  fi
fi

# --- Pendencias de rotacao abertas -----------------------------------------------------------
PENDING_FILE="$LT_CFG/lt/security-pending.jsonl"
if [ -r "$PENDING_FILE" ]; then
  N="$(grep -c '"status": *"pending"' "$PENDING_FILE" 2>/dev/null || printf 0)"
  if [ "${N:-0}" -gt 0 ] 2>/dev/null; then
    CTX="$CTX
Ha $N pendencia(s) de rotacao de credencial em aberto (LT-SEC-003)."
  fi
fi

printf '%s\n' "$CTX"
exit 0
