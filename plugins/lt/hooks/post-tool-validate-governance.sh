#!/usr/bin/env bash
# lt / hooks / post-tool-validate-governance.sh
# Categoria: GOVERNANCA
#
# Depois de uma escrita, AVISA (nunca bloqueia) em dois casos:
#   1. arquivo de governanca do repo alterado sem registro: AGENTS.md, CLAUDE.md, .lt/config.yaml,
#      .lt/preferences.json, .lt/sensitive-paths.json, .lt/skills/**, .claude/settings*.json.
#      "Registro" = aprovacao `exception` fresca (30 min) no approve.log — a mesma trilha que o
#      resto do harness audita;
#   2. prd.md/techspec.md/tasks.md APROVADO no sdd-state.json cujo conteudo deixou de bater com o
#      hash aprovado: a cadeia de confianca rompeu e o caminho e' `invalidate --from <artefato>`.
#
# POR QUE AVISO E NAO BLOQUEIO (o hook de origem bloqueava por padrao): em PostToolUse a escrita
# ja aconteceu — bloquear aqui nao desfaz nada, so interrompe o agente depois do fato. O aviso
# volta como contexto para o agente, que e' quem precisa corrigir o rumo.
#
# No-op fora de repo que adotou o harness (sem .lt/config.yaml) e no proprio repo do harness.
# Fail-open em qualquer erro interno: aviso que falha nao pode derrubar a sessao.

set -uo pipefail
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LT_PLUGIN_ROOT="$PLUGIN_ROOT"
. "$PLUGIN_ROOT/lib/hook-common.sh"

PROJECT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
[ -f "$PROJECT/plugins/lt/.claude-plugin/plugin.json" ] && exit 0
[ -f "$PROJECT/.lt/config.yaml" ] || exit 0

INPUT="$(cat 2>/dev/null || printf '{}')"
INPUT="${INPUT:0:200000}"
FILE="$(lt_json_str "$INPUT" file_path)"
[ -n "$FILE" ] || exit 0
REL="${FILE#"$PROJECT"/}"

MSG=""
case "$REL" in
  AGENTS.md|CLAUDE.md|.lt/config.yaml|.lt/preferences.json|.lt/sensitive-paths.json|.lt/skills/*|\
  .claude/settings.json|.claude/settings.local.json)
    if ! lt_has_approval "exception" 1800; then
      MSG="Arquivo de governanca alterado sem registro: $REL. Se a mudanca e' intencional, registre com lt:lt-approve exception \"<motivo>\"; senao, reverta."
    fi
    ;;
  *prd.md|*techspec.md|*tasks.md)
    command -v python3 >/dev/null 2>&1 || exit 0
    MSG="$(python3 - "$PROJECT" "$REL" <<'PY' 2>/dev/null
import hashlib, json, os, sys
root, rel = sys.argv[1], sys.argv[2]
path = rel if os.path.isabs(rel) else os.path.join(root, rel)
name = {"prd.md": "prd", "techspec.md": "techspec", "tasks.md": "tasks"}.get(os.path.basename(path))
state = os.path.join(os.path.dirname(path), "sdd-state.json")
if not name or not os.path.isfile(state) or not os.path.isfile(path):
    raise SystemExit(0)
info = (json.load(open(state, encoding="utf-8")).get("artifacts") or {}).get(name) or {}
if info.get("status") != "approved" or not info.get("hash"):
    raise SystemExit(0)
if hashlib.sha256(open(path, "rb").read()).hexdigest() != info["hash"]:
    print("%s esta APROVADO e acabou de mudar: a aprovacao nao vale mais para este conteudo. "
          "Rode lt-sdd.sh invalidate %s --from %s, revise e aprove de novo."
          % (rel, os.path.dirname(rel) or ".", name))
PY
)"
    ;;
esac
[ -n "$MSG" ] || exit 0

lt_audit_fire "post-tool-validate-governance" "WARN" "$REL"
printf '[lt] aviso — %s\n' "$MSG" >&2
MSG_JSON="$(printf '%s' "$MSG" | tr -d '\r\n' | sed 's/\\/\\\\/g; s/"/\\"/g')"
printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"[lt] %s"}}\n' "$MSG_JSON"
exit 0
