#!/usr/bin/env bash
# lt / lib / lt-lock.sh
#
# Lock portatil para append em log compartilhado.
#
# POR QUE ESTE ARQUIVO EXISTE: flock(1) NAO existe no macOS, e a frota da Lima Teixeira e' macOS.
# Um script que faz `flock -x 9` funciona no CI Linux e falha silenciosamente no Mac de quem usa
# o harness — a classe de defeito "verde no CI, morto no Mac". Aqui usamos flock quando ele existe
# e caimos para spin-lock por mkdir, que e' atomico em POSIX, quando nao existe.
#
# bash 3.2: sem declare -A, sem mapfile, sem local -n.
#
# Uso:
#   . "$PLUGIN_ROOT/lib/lt-lock.sh"
#   if lt_lock "$LOCKDIR" 5; then ... ; lt_unlock "$LOCKDIR"; fi

# Idade, em segundos, apos a qual um lock e' considerado orfao (processo morreu sem soltar).
# 60s e' generoso: nenhuma operacao legitima deste harness segura o lock por mais de ~1s.
LT_LOCK_STALE_SECS="${LT_LOCK_STALE_SECS:-60}"

lt__now() { date +%s; }

# mtime portatil: BSD stat usa -f %m, GNU stat usa -c %Y.
#
# O fallback devolve o INSTANTE ATUAL, nao zero. Com zero, a idade calculada vira "agora - 0" =
# o epoch inteiro, e o lock e' declarado envelhecido de 56 anos e tomado na hora — exatamente o
# oposto do que a protecao pretende. Isso apareceu em producao, com a mensagem
# "lock envelhecido (1790161837s)". Na duvida sobre a idade, trate o lock como FRESCO: esperar
# alguns segundos a mais e' barato; tomar o lock de um processo vivo corrompe o log.
lt__mtime() {
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || date +%s
}

# lt_lock <lockdir> [timeout_secs] -> 0 se adquiriu, 1 se nao
lt_lock() {
  lt_lock_dir="$1"
  lt_lock_timeout="${2:-5}"
  lt_lock_deadline=$(( $(lt__now) + lt_lock_timeout ))

  mkdir -p "$(dirname "$lt_lock_dir")" 2>/dev/null || true

  while :; do
    # mkdir falha se o diretorio existe. E' a primitiva atomica que POSIX garante.
    if mkdir "$lt_lock_dir" 2>/dev/null; then
      printf '%s\n' "$$" > "$lt_lock_dir/pid" 2>/dev/null || true
      return 0
    fi

    # Tomada de lock envelhecido. Sem isto, um processo morto trava o log para sempre e o
    # harness passa a perder linhas de auditoria em silencio — que e' pior que bloquear.
    lt_lock_age=$(( $(lt__now) - $(lt__mtime "$lt_lock_dir") ))
    if [ "$lt_lock_age" -gt "$LT_LOCK_STALE_SECS" ]; then
      printf '[lt] lock envelhecido (%ss) em %s — assumindo\n' "$lt_lock_age" "$lt_lock_dir" >&2
      rm -rf "$lt_lock_dir" 2>/dev/null || true
      continue
    fi

    [ "$(lt__now)" -ge "$lt_lock_deadline" ] && return 1

    # sleep 0.1 nao e' portatil em todo sh; aqui bash aceita fracao no macOS e no GNU coreutils.
    sleep 0.1 2>/dev/null || sleep 1
  done
}

# lt_unlock <lockdir>
lt_unlock() {
  [ -n "${1:-}" ] || return 0
  rm -rf "$1" 2>/dev/null || true
}
