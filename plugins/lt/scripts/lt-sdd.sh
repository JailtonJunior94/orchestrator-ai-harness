#!/usr/bin/env bash
# lt / scripts / lt-sdd.sh
#
# Porta unica do ciclo SDD. Mapeia 1:1 os subcomandos que as skills invocam.
#
# POR QUE UM DISPATCHER E NAO VARIOS SCRIPTS
# O harness de origem expunha tudo por um unico binario. Manter uma unica porta significa que as
# skills tem UMA forma de chamar, o classificador de auto mode ve sempre a mesma forma, e trocar
# a implementacao por dentro nao obriga a reescrever prosa em onze skills.
#
# FALHA ALTO, NUNCA PULA. Gate que some junto com a dependencia e' verde por ausencia: se
# python3 nao existe, isto e' erro, nao "tudo certo".
#
# Uso:
#   Integridade e aprovacao
#   lt-sdd.sh hash <arquivo>
#   lt-sdd.sh sync-spec-hash <dir-do-prd>
#   lt-sdd.sh check-spec-drift <dir-do-prd>
#   lt-sdd.sh validate-sdd <dir-do-prd> [--contract [v1|v2]]
#   lt-sdd.sh check-traceability <dir-do-prd>
#   lt-sdd.sh approve <dir-do-prd> <prd|techspec|tasks>
#   lt-sdd.sh assert-approved <dir-do-prd> <prd|techspec|tasks>
#   lt-sdd.sh invalidate <dir-do-prd> --from <artefato>
#   lt-sdd.sh state <dir-do-prd>
#
#   Estado v2 e execucao
#   lt-sdd.sh migrate-sdd <dir-do-prd> [--run-id <id>] [--dry-run]
#   lt-sdd.sh rollback-sdd <dir-do-prd> [--run-id <id>]
#   lt-sdd.sh orchestrate <dir-do-prd> --run-id <id>
#   lt-sdd.sh waves <dir-do-prd> [--next]
#   lt-sdd.sh runtime-capabilities [--host claude|codex|copilot|opencode]
#   lt-sdd.sh snapshot
#   lt-sdd.sh task-patch <tree-antes> <tree-depois> <arquivo-patch> [--exclude <caminho>]...
#
#   Evidencia e contratos (schemas em config/schemas/)
#   lt-sdd.sh seal-evidence <relatorio.md> [--commit <sha> [--base <commit>]] [--verify]
#   lt-sdd.sh validate-result <execution|review|checkpoint> <arquivo.json> [--task-id <id>]
#   lt-sdd.sh validate-bugs <bugs.json>
#   lt-sdd.sh session-audit [--strict]
#
#   Memoria e telemetria (local, nada sai da maquina)
#   lt-sdd.sh memory <dir-do-prd> add <chave> <texto...> [--task <id>] [--session <id>]
#   lt-sdd.sh memory <dir-do-prd> list | show <chave>
#   lt-sdd.sh telemetry report [--since N] [--budget <tokens/dia>] [--json]
#   lt-sdd.sh metrics [--since N] [--json]
#
#   Descoberta
#   lt-sdd.sh specs-root [--slug <slug>] [--create]
#   lt-sdd.sh skills-available [--category <categoria>]

set -uo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

if ! command -v python3 >/dev/null 2>&1; then
  printf '[lt sdd] FALHA: python3 ausente.\n' >&2
  printf '         Os gates do ciclo SDD nao podem rodar, e um gate que nao roda nao aprova.\n' >&2
  printf '         Instale python3 e rode `lt:lt-doctor`.\n' >&2
  exit 1
fi

exec python3 "$PLUGIN_ROOT/lib/sdd.py" "$@"
