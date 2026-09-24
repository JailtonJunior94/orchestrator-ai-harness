#!/usr/bin/env bash
# tests / unit / scripts / hosts-health.test.sh
#
# `lt-doctor --hosts` existe para os modos de falha SILENCIOSA dos hosts adaptados: hook do Codex
# sem trusted_hash (pulado sem aviso), copia instalada que ficou para tras da fonte, e host cujos
# hooks nunca dispararam desde a instalacao. Cada um tem um caso aqui, sob HOME descartavel.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
. "$REPO/tests/unit/lib/assert.sh"

W="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$W"' EXIT
export HOME="$W/home" CODEX_HOME="$W/home/.codex" COPILOT_HOME="$W/home/.copilot" \
       XDG_CONFIG_HOME="$W/home/.config" CLAUDE_CONFIG_DIR="$W/home/.claude"
mkdir -p "$HOME" "$CLAUDE_CONFIG_DIR"
HEALTH="$REPO/plugins/lt/lib/hosts_health.py"
health() { python3 "$HEALTH" 2>&1; }

describe "sem instalacao global"
assert_contains "$(health)" "nenhuma instalacao global" "ausencia e' dita, nao tratada como erro"

describe "instalacao recem-feita"
python3 "$REPO/plugins/lt/scripts/reconcile-hosts.py" install --scope global --hosts codex,copilot,opencode >/dev/null
OUT="$(health)"; RC=$?
assert_eq "0" "$RC" "saudavel sai 0"
assert_contains "$OUT" "Codex: trusted_hash registrado para 5" "trust do Codex conferido no config.toml"
assert_contains "$OUT" "copia instalada em dia" "digest da fonte confere"
assert_contains "$OUT" "codex: nenhuma sessao com hooks" "host que nunca disparou e' acusado"

describe "sinal de vida depois da instalacao"
printf '{}' | LT_HOST=codex CLAUDE_PLUGIN_ROOT="$HOME/.lt-harness" bash "$HOME/.lt-harness/hooks/session-start.sh" >/dev/null 2>&1
assert_contains "$(health)" "codex: hooks dispararam" "session-start do host grava o sinal de vida"
assert_contains "$(health)" "copilot: nenhuma sessao" "e os outros hosts continuam acusados"

describe "trust do Codex removido por fora"
python3 - "$CODEX_HOME/config.toml" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
start = s.index("# lt:hosts-generated-start"); end = s.index("# lt:hosts-generated-end") + len("# lt:hosts-generated-end")
open(p, "w").write(s[:start] + s[end:])
PY
OUT="$(health)"; RC=$?
assert_eq "1" "$RC" "trust ausente reprova"
assert_contains "$OUT" "pulados em silencio" "a mensagem diz a consequencia real"
end_describe
