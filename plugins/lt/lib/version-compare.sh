#!/usr/bin/env bash
# lt / lib / version-compare.sh
#
# Comparacao SEMANTICA de versao, em bash 3.2. Carregado com `.`, nunca executado.
#
# POR QUE ISTO EXISTE
# Ordenacao lexica (`ls -1dr`, `sort`) escolhe 0.9.4 em vez de 0.10.0. Quando o shim da
# statusline resolve a versao do cache por ordem lexica, a barra passa a exibir dados de uma
# versao antiga enquanto os hooks ja rodam a nova — e o sintoma ("a barra viajou no tempo") nao
# aponta para a causa.
#
# vc_gt A B -> 0 (verdadeiro) se A > B

vc_gt() {
  local a b i
  local A0 A1 A2 B0 B1 B2
  # Descarta pre-release e build metadata: 1.2.3-rc1 compara como 1.2.3.
  IFS=. read -r A0 A1 A2 <<< "${1%%[-+]*}"
  IFS=. read -r B0 B1 B2 <<< "${2%%[-+]*}"
  set -- "${A0:-0}" "${A1:-0}" "${A2:-0}" "${B0:-0}" "${B1:-0}" "${B2:-0}"
  for i in 1 2 3; do
    # 10# e' obrigatorio: sem ele, 08 e 09 sao octal invalido e abortam sob `set -e`.
    eval "a=\$$i"
    eval "b=\$$((i+3))"
    a=$(( 10#${a:-0} )); b=$(( 10#${b:-0} ))
    [ "$a" -gt "$b" ] && return 0
    [ "$a" -lt "$b" ] && return 1
  done
  return 1
}
