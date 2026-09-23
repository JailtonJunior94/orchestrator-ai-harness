#!/usr/bin/env bash
# lt / lib / specs-root.sh
#
# Resolvedor UNICO da raiz de specs para o lado shell do harness.
#
# POR QUE ESTE ARQUIVO EXISTE
# Os hooks do ciclo faziam `TASKS_ROOT="${AI_TASKS_ROOT:-.specs}"` enquanto `lib/sdd.py`
# resolvia o default para `.lt/specs`. Num repo sem `.specs/`, o motor gravava a spec em
# `.lt/specs/prd-<slug>/` e os hooks procuravam em `.specs/prd-<slug>/`: os dois nunca se
# encontravam, e o sintoma aparecia so na execucao da tarefa, como "tasks.md nao existe" num
# caminho que ninguem tinha pedido. Um default duplicado e' um bug esperando a primeira
# instalacao limpa.
#
# Agora existe uma unica autoridade — `lt-sdd.sh specs-root` — e este arquivo e' o adaptador
# para quem esta em bash. Mudar a cascata de deteccao passa a ser uma edicao so.
#
# USO (sourced, nunca executado):
#   . "${CLAUDE_PLUGIN_ROOT}/lib/specs-root.sh"
#   lt_specs_root "$REPO_ROOT"     # ecoa o caminho absoluto; exit != 0 se nao resolver
#
# FALHA ALTO, NUNCA PALPITA. Hook que nao sabe onde a spec mora nao pode seguir com um chute:
# o chute grava evidencia no lugar errado e a rastreabilidade quebra em silencio.

# shellcheck shell=bash

lt_specs_root() {
  lt__sr_repo_root="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  lt__sr_plugin="${CLAUDE_PLUGIN_ROOT:-}"

  if [ -z "$lt__sr_plugin" ]; then
    # Chamado de dentro de scripts/cycle/ — o plugin e' dois niveis acima.
    lt__sr_plugin="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  fi

  lt__sr_dispatcher="$lt__sr_plugin/scripts/lt-sdd.sh"
  if [ ! -f "$lt__sr_dispatcher" ]; then
    printf '[lt] FALHA: %s ausente — nao ha como resolver a raiz de specs.\n' \
      "$lt__sr_dispatcher" >&2
    return 1
  fi

  # LT_PROJECT_DIR explicito: o hook ja sabe o repo, e deixar o resolvedor redescobrir por cwd
  # abriria a chance de ele responder por outro repo quando o hook roda de um subdiretorio.
  lt__sr_out="$(LT_PROJECT_DIR="$lt__sr_repo_root" bash "$lt__sr_dispatcher" specs-root 2>/dev/null)"
  lt__sr_rc=$?

  if [ "$lt__sr_rc" -ne 0 ] || [ -z "$lt__sr_out" ]; then
    printf '[lt] FALHA: `lt-sdd.sh specs-root` nao resolveu a raiz de specs de %s (rc=%d).\n' \
      "$lt__sr_repo_root" "$lt__sr_rc" >&2
    printf '     Rode `lt:lt-doctor`. Seguir com um default local reintroduziria a\n' >&2
    printf '     divergencia que este resolvedor existe para eliminar.\n' >&2
    return 1
  fi

  printf '%s\n' "$lt__sr_out"
  return 0
}
