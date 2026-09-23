#!/usr/bin/env bash
# tests / unit / lib / assert.sh
#
# Helper de teste em bash puro. Sem framework externo de proposito: o harness precisa rodar seus
# proprios testes num macOS com bash 3.2 e sem nenhuma dependencia instalada.
#
# REGRA CENTRAL: skip NAO e' fail, e skip TAMBEM nao e' pass.
# Teste que nao PODE rodar (dependencia ausente) e' contado a parte. Um `skip` que soma em verde
# transforma "a ferramenta sumiu" em "tudo certo" — que e' a forma mais barata de perder um gate.

LT_T_OK=0
LT_T_BAD=0
LT_T_SKIP=0
LT_T_DESC=""

if [ -t 1 ]; then
  LT_C_OK=$'\033[32m'; LT_C_BAD=$'\033[31m'; LT_C_SKIP=$'\033[33m'; LT_C_OFF=$'\033[0m'
else
  LT_C_OK=""; LT_C_BAD=""; LT_C_SKIP=""; LT_C_OFF=""
fi

describe() { LT_T_DESC="$1"; printf '\n▸ %s\n' "$1"; }

ok()   { LT_T_OK=$((LT_T_OK+1));   printf '  %s✓%s %s\n' "$LT_C_OK" "$LT_C_OFF" "$1"; }
bad()  { LT_T_BAD=$((LT_T_BAD+1)); printf '  %s✗%s %s\n' "$LT_C_BAD" "$LT_C_OFF" "$1" >&2; }
skip() { LT_T_SKIP=$((LT_T_SKIP+1)); printf '  %s~%s %s (pulado: %s)\n' "$LT_C_SKIP" "$LT_C_OFF" "$1" "${2:-sem motivo}"; }

assert_eq() {
  if [ "$1" = "$2" ]; then ok "${3:-valores iguais}"
  else bad "${3:-valores diferentes}: esperado '$1', obtido '$2'"; fi
}

assert_ne() {
  if [ "$1" != "$2" ]; then ok "${3:-valores diferentes}"
  else bad "${3:-deveriam diferir}: ambos '$1'"; fi
}

assert_contains() {
  case "$1" in *"$2"*) ok "${3:-contem '$2'}" ;; *) bad "${3:-nao contem '$2'}: '$1'" ;; esac
}

assert_not_contains() {
  case "$1" in *"$2"*) bad "${3:-nao deveria conter '$2'}: '$1'" ;; *) ok "${3:-nao contem '$2'}" ;; esac
}

# assert_exit_code <esperado> <comando...>
assert_exit_code() {
  lt_want="$1"; shift
  "$@" >/dev/null 2>&1
  lt_got=$?
  if [ "$lt_got" -eq "$lt_want" ]; then ok "exit $lt_want de: $*"
  else bad "exit esperado $lt_want, obtido $lt_got de: $*"; fi
}

assert_file_exists() {
  if [ -e "$1" ]; then ok "${2:-existe: $1}"; else bad "${2:-nao existe: $1}"; fi
}

# Guarda contra teste que escreve no perfil REAL de quem roda.
#
# ESTA FUNCAO JA FALHOU UMA VEZ, e o modo como falhou e' a licao: ela olhava so o HOME. Mas o
# harness resolve o perfil por CLAUDE_CONFIG_DIR, que a sessao do dev normalmente tem setado
# (aliases claude / claude-work / claude-alt). Com HOME isolado e
# CLAUDE_CONFIG_DIR apontando para o perfil real, o teste escreveu 10 linhas de dado falso no
# approve.log de producao — e passou verde, porque as linhas que ele mesmo criou satisfaziam as
# asserções.
#
# Trilha de auditoria poluida por teste e' pior que teste ausente: alguem vai ler aquelas linhas
# um dia acreditando que sao reais.
#
# Por isso a guarda checa AS DUAS variaveis, e o teste deve isolar as duas.
lt__is_temp() {
  case "$1" in
    /var/folders/*|/tmp/*|/private/var/*|/private/tmp/*) return 0 ;;
    *) return 1 ;;
  esac
}

assert_not_scratchpad() {
  lt_ans_fail=0
  if lt__is_temp "$HOME"; then
    ok "HOME isolado"
  else
    bad "HOME NAO esta isolado ($HOME) — este teste escreveria no ambiente real"
    lt_ans_fail=1
  fi
  if [ -n "${CLAUDE_CONFIG_DIR:-}" ] && ! lt__is_temp "$CLAUDE_CONFIG_DIR"; then
    bad "CLAUDE_CONFIG_DIR aponta para o perfil REAL ($CLAUDE_CONFIG_DIR) — o teste sujaria o audit trail de producao"
    lt_ans_fail=1
  else
    ok "perfil de configuracao isolado"
  fi
  return "$lt_ans_fail"
}

end_describe() {
  printf '\n  %d ok · %d falha · %d pulado\n' "$LT_T_OK" "$LT_T_BAD" "$LT_T_SKIP"
  [ "$LT_T_BAD" -eq 0 ]
}
