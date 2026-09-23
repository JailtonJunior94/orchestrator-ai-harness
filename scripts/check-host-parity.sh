#!/usr/bin/env bash
# scripts / check-host-parity.sh
#
# Gate de paridade Claude Code / Codex / Copilot / OpenCode. Falha quando um componente canonico
# (skill, agent, comando, evento de hook) nao chega a algum host, ou quando a matriz publicada em
# docs/capability-matrix.md nao corresponde a projecao real. `--write` regenera a matriz.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$HERE/lib/host-parity.py" "$@"
