#!/usr/bin/env bash
# lt / lib / hook-common.sh
#
# Primitivas compartilhadas pelos hooks. Carregado com `.`, nunca executado.
#
# Nao ha' `set -e` aqui de proposito: hook que aborta no meio por um comando auxiliar que falhou
# deixa a decisao de seguranca pela metade. Cada funcao trata o proprio erro.

# Perfil de configuracao do Claude Code. Esta maquina pode ter varios (~/.claude,
# ~/.claude-work, ~/.claude-alt), selecionados por CLAUDE_CONFIG_DIR — e instalar no
# perfil errado significa que o harness simplesmente nao aparece na sessao de quem o instalou.
LT_CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

LT_HOME="$LT_CFG/lt"

# Escreve a decisao que o host entende. Sempre acompanhada de exit 0 — o host le o JSON, nao o
# codigo de saida, para permissionDecision.
lt_emit_decision() {  # $1=ask|deny  $2=motivo (texto puro)
  lt_ed_reason="$(printf '%s' "$2" | tr -d '\r\n' | sed 's/\\/\\\\/g; s/"/\\"/g')"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"}}\n' \
    "$1" "$lt_ed_reason"
}

# Extrai um campo string de um JSON simples SEM FORK de interpretador.
#
# POR QUE IMPORTA: estes hooks rodam em TODA chamada de ferramenta. Um fork de python3 custa
# ~40ms nesta maquina; usa-lo so para ler um campo que o proprio resolvedor ja devolveu dobra o
# custo do hook no caminho feliz — justamente o caminho que roda 99% das vezes.
#
# Limite honesto: e' sed, nao parser. Serve para os campos que ESTE harness emite (texto simples,
# sem aspas escapadas). Para qualquer coisa alem disso, use o resolvedor.
lt_json_str() {  # $1=json  $2=chave
  printf '%s' "$1" | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" | head -1
}

# Registra o disparo no audit local do repo consumidor, com lock.
# Falha aqui nunca muda a decisao de seguranca — perder uma linha de log e' ruim, mas liberar um
# comando destrutivo porque o log falhou seria pior.
lt_audit_fire() {  # $1=hook  $2=status  $3=detalhe
  [ -d .git ] || [ -n "${CLAUDE_PROJECT_DIR:-}" ] || return 0
  lt_af_dir="${CLAUDE_PROJECT_DIR:-.}/.lt/audit"
  mkdir -p "$lt_af_dir" 2>/dev/null || return 0
  . "${LT_PLUGIN_ROOT:-$PLUGIN_ROOT}/lib/lt-lock.sh" 2>/dev/null || return 0
  if lt_lock "$lt_af_dir/.lock" 2; then
    printf '%s | hook=%s | status=%s | %s\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" "${3:-}" >> "$lt_af_dir/hook-fires.log" 2>/dev/null
    lt_unlock "$lt_af_dir/.lock"
  fi
  return 0
}

# Ha' aprovacao valida para <token> nos ultimos <janela> segundos?
#
# CASAMENTO EXATO no campo 2. A leitura ingenua (`awk '$2 ~ /destructive/'`) aceitaria um slug
# como `fix-destructive-cleanup` e abriria a guarda. O approve.sh ja valida na escrita; aqui
# validamos de novo na leitura, porque o log pode ter linhas antigas de versoes anteriores.
lt_has_approval() {  # $1=token  $2=janela_segundos
  lt_ha_log="$LT_HOME/approve.log"
  [ -r "$lt_ha_log" ] || return 1
  lt_ha_now=$(date +%s)
  lt_ha_min=$(( lt_ha_now - ${2:-300} ))
  awk -F'\t' -v tok="$1" -v min="$lt_ha_min" \
    '$2 == tok && $1 + 0 >= min { found = 1 } END { exit !found }' "$lt_ha_log"
}
