#!/usr/bin/env bash
# tests / unit / scripts / multi-host-reconcile.test.sh
#
# Prova a projecao do plugin em Codex, Copilot e OpenCode nos dois escopos. Os casos que ja
# custaram caro: uninstall que apagava arquivo pre-existente do usuario, reinstalacao que nao era
# idempotente, TOML do Codex invalido ou com trust ausente (hook pulado em silencio), e o hook
# canonico que protege o Claude mas nao bloqueia no host adaptado.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
. "$REPO/tests/unit/lib/assert.sh"

RECONCILE="$REPO/plugins/lt/scripts/reconcile-hosts.py"
W="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$W"' EXIT

# Escopo global roda sempre contra HOME isolado: nunca tocar o perfil real de quem roda o teste.
export HOME="$W/home" CODEX_HOME="$W/home/.codex" COPILOT_HOME="$W/home/.copilot" XDG_CONFIG_HOME="$W/home/.config"
mkdir -p "$HOME" "$W/project/.agents/skills/local-skill" "$W/project/.github/agents"
printf '# Local\n' > "$W/project/AGENTS.md"
printf -- '---\nname: local-skill\ndescription: do usuario\n---\n' > "$W/project/.agents/skills/local-skill/SKILL.md"
printf -- '---\nname: meu-agente\n---\n' > "$W/project/.github/agents/meu-agente.agent.md"

EXPECTED_SKILLS="$(find "$REPO/plugins/lt/skills" -mindepth 2 -maxdepth 2 -name SKILL.md | wc -l | tr -d ' ')"
EXPECTED_COMMANDS="$(find "$REPO/plugins/lt/commands" -name '*.md' | wc -l | tr -d ' ')"
EXPECTED_AGENTS="$(find "$REPO/plugins/lt/agents" -name '*.md' | wc -l | tr -d ' ')"

rec() { python3 "$RECONCILE" "$@"; }

describe "escopo project"
rec install --project "$W/project" --hosts codex,copilot,opencode --trust >/dev/null
assert_eq "0" "$?" "instalacao passa"
assert_file_exists "$W/project/.lt-harness/manifest.json" "manifest criado"
assert_file_exists "$W/project/.codex/hooks.json" "Codex: hooks.json"
assert_file_exists "$W/project/.codex/agents/task-executor.toml" "Codex: agent projetado"
assert_file_exists "$W/project/.github/hooks/lt-governance.json" "Copilot: hooks"
assert_file_exists "$W/project/.github/agents/task-executor.agent.md" "Copilot: agent projetado"
assert_file_exists "$W/project/.opencode/plugins/lt-governance.js" "OpenCode: plugin"
assert_file_exists "$W/project/.opencode/agents/task-executor.md" "OpenCode: agent projetado"
assert_file_exists "$W/project/.opencode/commands/lt-doctor.md" "OpenCode: comando projetado"
assert_file_exists "$W/project/.agents/skills/lt-doctor/SKILL.md" "comando vira skill para Codex/Copilot"

COUNT="$(find "$W/project/.agents/skills" -name SKILL.md | wc -l | tr -d ' ')"
assert_eq "$((EXPECTED_SKILLS + EXPECTED_COMMANDS + 1))" "$COUNT" "skills do plugin + comandos + a skill local"
AG="$(find "$W/project/.codex/agents" -name '*.toml' | wc -l | tr -d ' ')"
assert_eq "$EXPECTED_AGENTS" "$AG" "todo agent canonico tem projecao no Codex"

python3 - "$CODEX_HOME/config.toml" "$W/project" <<'PY'
import sys, tomllib
data = tomllib.load(open(sys.argv[1], "rb"))
assert data["projects"][sys.argv[2]]["trust_level"] == "trusted"
states = data["hooks"]["state"]
assert len([k for k in states if k.startswith(sys.argv[2] + "/.codex/hooks.json:")]) == 5, states
PY
assert_eq "0" "$?" "config.toml do Codex e' TOML valido com trust do projeto e dos 5 hooks"
assert_contains "$(cat "$COPILOT_HOME/config.json")" "$W/project" "Copilot: pasta em trustedFolders"
assert_not_contains "$(cat "$W/project/.agents/skills/execute-task/SKILL.md")" '${CLAUDE_PLUGIN_ROOT}' "skill renderizada sem variavel do Claude"

rec verify --project "$W/project" >/dev/null
assert_eq "0" "$?" "checksums verificados"
rec install --project "$W/project" --hosts codex,copilot,opencode --trust >/dev/null
assert_eq "0" "$?" "segunda instalacao e' idempotente"
rec verify --project "$W/project" >/dev/null
assert_eq "0" "$?" "verify continua verde apos reinstalar"

describe "hook canonico bloqueia nos tres hosts"
( cd "$W/project" && printf '%s' '{"tool":"bash","args":{"command":"rm -rf /"}}' \
  | python3 .lt-harness/host-dispatch.py opencode before_tool >/dev/null 2>&1 )
assert_eq "2" "$?" "OpenCode"
( cd "$W/project" && printf '%s' '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"},"cwd":"'"$W/project"'"}' \
  | python3 .lt-harness/host-dispatch.py codex before_tool >/dev/null 2>&1 )
assert_eq "2" "$?" "Codex"
( cd "$W/project" && printf '%s' '{"toolName":"bash","toolArgs":{"command":"rm -rf /"},"cwd":"'"$W/project"'"}' \
  | python3 .lt-harness/host-dispatch.py copilot before_tool >/dev/null 2>&1 )
assert_eq "2" "$?" "Copilot"
( cd "$W/project" && printf '%s' '{"toolName":"bash","toolArgs":{"command":"ls"},"cwd":"'"$W/project"'"}' \
  | python3 .lt-harness/host-dispatch.py copilot before_tool >/dev/null 2>&1 )
assert_eq "0" "$?" "comando inocente passa"

# Regressao provada no Codex real: hook que nega por JSON no stdout deixava o stderr vazio, e o
# Codex registra exit 2 sem razao como "hook Failed" e EXECUTA o apply_patch com o segredo.
PATCH_PAYLOAD="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Add File: s.txt\n+aws_access_key_id=AKIAIOSFODNN7EXAMPLE\n*** End Patch\n"},"cwd":sys.argv[1]}))' "$W/project")"
ERR="$( cd "$W/project" && printf '%s' "$PATCH_PAYLOAD" | python3 .lt-harness/host-dispatch.py codex before_tool 2>&1 >/dev/null )"
RC=$?
assert_eq "2" "$RC" "Codex: apply_patch com segredo e' negado"
assert_contains "$ERR" "segredo" "Codex: a razao do deny chega ao stderr (sem ela o Codex executa)"

describe "uninstall preserva o que era do usuario"
rec uninstall --project "$W/project" >/dev/null
assert_eq "0" "$?" "uninstall passa"
assert_file_exists "$W/project/AGENTS.md" "AGENTS local preservado"
assert_not_contains "$(cat "$W/project/AGENTS.md")" "lt:hosts-generated-start" "bloco gerenciado removido"
assert_file_exists "$W/project/.agents/skills/local-skill/SKILL.md" "skill pre-existente preservada"
assert_file_exists "$W/project/.github/agents/meu-agente.agent.md" "agent pre-existente preservado"
[ ! -e "$W/project/.lt-harness" ] && ok "runtime removido" || bad "runtime sobrou"
[ ! -e "$W/project/.codex/hooks.json" ] && ok "hooks.json do Codex removido" || bad "hooks.json sobrou"
assert_not_contains "$(cat "$CODEX_HOME/config.toml" 2>/dev/null)" "lt:hosts-generated" "trust do Codex removido"
assert_not_contains "$(cat "$COPILOT_HOME/config.json")" "$W/project" "trust do Copilot removido"

describe "conflito com arquivo do usuario recusa sem tocar nada"
mkdir -p "$W/project/.agents/skills/review"
printf -- '---\nname: review\ndescription: minha\n---\n' > "$W/project/.agents/skills/review/SKILL.md"
rec install --project "$W/project" --hosts codex >/dev/null 2>&1
assert_eq "1" "$?" "instalacao recusada"
assert_contains "$(cat "$W/project/.agents/skills/review/SKILL.md")" "minha" "skill do usuario intacta"
[ ! -e "$W/project/.lt-harness/manifest.json" ] && ok "nada instalado" || bad "instalou parcialmente"
rm -rf "$W/project/.agents/skills/review"

describe "escopo global"
mkdir -p "$CODEX_HOME" "$COPILOT_HOME/hooks"
printf 'model = "x"\n\n[hooks.state]\n' > "$CODEX_HOME/config.toml"
printf '{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"echo meu"}]}]}}\n' > "$CODEX_HOME/hooks.json"
printf '{"version":1,"hooks":{}}\n' > "$COPILOT_HOME/hooks/meu.json"
rec install --scope global --hosts codex,copilot,opencode >/dev/null
assert_eq "0" "$?" "instalacao global passa"
assert_file_exists "$HOME/.agents/skills/using-lt/SKILL.md" "skills em ~/.agents/skills"
assert_file_exists "$COPILOT_HOME/hooks/lt-governance.json" "Copilot: hook pessoal"
assert_file_exists "$XDG_CONFIG_HOME/opencode/plugins/lt-governance.js" "OpenCode: plugin global"
assert_file_exists "$CODEX_HOME/agents/reviewer.toml" "Codex: agent global"
assert_contains "$(cat "$CODEX_HOME/AGENTS.md")" "Governança LT" "Codex: AGENTS.md global"
python3 - "$CODEX_HOME" <<'PY'
import json, sys, tomllib
home = sys.argv[1]
data = tomllib.load(open(home + "/config.toml", "rb"))
assert data["model"] == "x"
hooks = json.load(open(home + "/hooks.json"))["hooks"]
assert hooks["PreToolUse"][0]["hooks"][0]["command"] == "echo meu", hooks
key = "%s/hooks.json:pre_tool_use:1:0" % home
assert key in data["hooks"]["state"], sorted(data["hooks"]["state"])
PY
assert_eq "0" "$?" "config e hooks do usuario preservados; trust aponta o grupo certo"
assert_not_contains "$(cat "$HOME/.agents/skills/execute-task/SKILL.md")" '${CLAUDE_PLUGIN_ROOT}' "skill global com caminho absoluto do runtime"
rec install --scope global --hosts codex,copilot,opencode >/dev/null
assert_eq "0" "$?" "reinstalacao global idempotente"
rec uninstall --scope global >/dev/null
assert_eq "0" "$?" "uninstall global passa"
assert_contains "$(cat "$CODEX_HOME/hooks.json")" "echo meu" "hook do usuario sobrevive"
assert_not_contains "$(cat "$CODEX_HOME/hooks.json")" "host-dispatch" "hook do harness removido"
assert_file_exists "$COPILOT_HOME/hooks/meu.json" "hook pessoal do Copilot preservado"
python3 -c 'import sys,tomllib; tomllib.load(open(sys.argv[1],"rb"))' "$CODEX_HOME/config.toml"
assert_eq "0" "$?" "config.toml segue valido depois do uninstall"
end_describe
