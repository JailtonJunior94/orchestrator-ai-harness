#!/usr/bin/env bash
# tests / unit / hooks / governance-hooks.test.sh
#
# Hooks de governanca: git-operation-gate, validate-preload, validate-governance, session-end e
# subagent-stop-wrapper. Cada um e' exercitado com payload no formato do host e, sobretudo, nos
# casos em que NAO deve agir — falso positivo em hook e' o caminho mais curto para o hook ser
# desligado junto com a protecao que ele da'.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
. "$REPO/tests/unit/lib/assert.sh"

HOOKS="$REPO/plugins/lt/hooks"
W="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$W"' EXIT
export HOME="$W/home" CLAUDE_CONFIG_DIR="$W/home/.claude" CLAUDE_PLUGIN_ROOT="$REPO/plugins/lt"
unset LT_HOME LT_GIT_GATE LT_PRELOAD_GATE LT_SUBAGENT_CONTRACT LT_PROTECTED_BRANCHES
mkdir -p "$CLAUDE_CONFIG_DIR"
LT="$CLAUDE_CONFIG_DIR/lt"
gitc() { git -c commit.gpgsign=false -c user.email=t@t -c user.name=t "$@"; }

describe "isolamento"
assert_not_scratchpad

mk_repo() {  # $1=nome  $2=consumer|plain  -> repo git em main com um commit
  local r="$W/$1"
  mkdir -p "$r"
  ( cd "$r" && git init -q -b main 2>/dev/null || git init -q; git checkout -q -B main
    printf 'x\n' > a.txt && git add a.txt && gitc commit -qm base )
  [ "$2" = "consumer" ] && { mkdir -p "$r/.lt"; printf 'tasks_root: .lt/specs\n' > "$r/.lt/config.yaml"; }
  return 0
}

# ── git-operation-gate ──────────────────────────────────────────────────────────────────────
describe "pre-bash-git-operation-gate"
mk_repo g plain
# 2>/dev/null no gerador: hook que sai antes de ler o stdin fecha o pipe, e o BrokenPipe do python
# e' ruido do teste, nao do hook.
bash_payload() { python3 -c 'import json,sys;print(json.dumps({"session_id":"s","tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$1" 2>/dev/null; }
gate() { bash_payload "$1" | CLAUDE_PROJECT_DIR="$W/g" bash "$HOOKS/pre-bash-git-operation-gate.sh" 2>/dev/null; }

assert_contains "$(gate 'git commit -m "x"')" '"permissionDecision":"ask"' "commit em main pede confirmacao"
assert_contains "$(gate 'git push origin main')" '"permissionDecision":"ask"' "push para main pede confirmacao"
assert_contains "$(gate 'git push --force-with-lease origin main')" '"permissionDecision":"deny"' "force-with-lease para main e' negado"
assert_contains "$(gate 'git push origin +main')" '"permissionDecision":"deny"' "refspec +main e' negado"
assert_contains "$(gate 'cd x && bash -c "git push origin main"')" '"permissionDecision":"ask"' "git dentro de bash -c e' visto"
assert_contains "$(gate 'FOO=1 env git -C . commit -qm y')" '"permissionDecision":"ask"' "atribuicao, wrapper e -C nao escondem o commit"
assert_eq "" "$(gate 'echo "git push origin main"')" "git como DADO de echo nao dispara"
assert_eq "" "$(gate 'git push origin feat/x')" "push para branch de trabalho passa"
assert_eq "" "$(gate 'git commit --dry-run')" "commit --dry-run passa"
assert_eq "" "$(gate 'git status && git log -1')" "leitura passa"
( cd "$W/g" && git checkout -q -b feat/y )
assert_eq "" "$(gate 'git commit -m y')" "commit em feat/y passa"
assert_eq "" "$(gate 'git push')" "push sem refspec de feat/y passa"
( cd "$W/g" && git checkout -q main )
assert_contains "$(gate 'git push')" '"permissionDecision":"ask"' "push sem refspec a partir de main usa a branch atual"
assert_eq "" "$(bash_payload 'git commit -m x' | LT_GIT_GATE=off CLAUDE_PROJECT_DIR="$W/g" bash "$HOOKS/pre-bash-git-operation-gate.sh")" "LT_GIT_GATE=off desliga"
assert_eq "" "$(bash_payload 'git commit -m x' | LT_PROTECTED_BRANCHES='release/*' CLAUDE_PROJECT_DIR="$W/g" bash "$HOOKS/pre-bash-git-operation-gate.sh")" "lista de protegidas e' configuravel"

# ── validate-preload ────────────────────────────────────────────────────────────────────────
describe "pre-write-validate-preload"
mk_repo c consumer
mk_repo p plain
mkdir -p "$W/h/plugins/lt/.claude-plugin" "$W/h/.lt"
printf '{}' > "$W/h/plugins/lt/.claude-plugin/plugin.json"; printf 'x: 1\n' > "$W/h/.lt/config.yaml"
write_payload() {  # $1=arquivo $2=sessao [$3=agent_type]
  python3 -c 'import json,sys
d={"session_id":sys.argv[2],"tool_name":"Edit","tool_input":{"file_path":sys.argv[1],"old_string":"a","new_string":"b"}}
if len(sys.argv)>3: d["agent_type"]=sys.argv[3]
print(json.dumps(d))' "$@" 2>/dev/null
}
pre() { local proj="$1"; shift; write_payload "$@" | CLAUDE_PROJECT_DIR="$W/$proj" bash "$HOOKS/pre-write-validate-preload.sh" 2>&1; }

assert_contains "$(pre c "$W/c/src/main.go" s1)" '"permissionDecision":"deny"' "codigo sem governanca carregada e' negado"
assert_contains "$(pre c "$W/c/src/main.go" s1)" "lt:agent-governance" "o motivo diz como resolver"
assert_eq "" "$(pre p "$W/p/src/main.go" s1)" "repo sem .lt/config.yaml: no-op"
mkdir -p "$W/p/.lt/audit"
assert_eq "" "$(pre p "$W/p/src/main.go" s1)" ".lt/audit criado por hook nao conta como adocao"
assert_eq "" "$(pre h "$W/h/plugins/lt/lib/x.py" s1)" "repo do proprio harness: no-op"
assert_eq "" "$(pre c "$W/c/README.md" s1)" "prosa nao e' gateada"
assert_eq "" "$(pre c "$W/c/.lt/specs/prd-x/tasks.md" s1)" "spec nao e' gateada"
assert_eq "" "$(pre c "$W/c/src/main.go" "")" "sem session_id: no-op"
assert_eq "" "$(pre c "$W/c/src/main.go" s1 lt:task-executor)" "task-executor ja traz agent-governance"
skill_fire() { printf '{"session_id":"%s","tool_name":"Skill","tool_input":{"skill":"%s"}}' "$1" "$2" | bash "$HOOKS/post-skill-fire.sh"; }
skill_fire s1 lt:create-prd
assert_contains "$(pre c "$W/c/src/main.go" s1)" "deny" "skill que nao carrega governanca nao libera"
skill_fire s1 lt:agent-governance
assert_file_exists "$LT/preload/s1" "post-skill-fire grava o marcador da sessao"
assert_eq "" "$(pre c "$W/c/src/main.go" s1)" "com governanca carregada, libera"
assert_contains "$(pre c "$W/c/src/main.go" s2)" "deny" "o marcador e' por sessao"
OUT="$(write_payload "$W/c/src/main.go" s2 | LT_PRELOAD_GATE=warn CLAUDE_PROJECT_DIR="$W/c" bash "$HOOKS/pre-write-validate-preload.sh" 2>&1 >/dev/null)"
assert_contains "$OUT" "LT_PRELOAD_GATE=warn" "modo warn avisa"
assert_eq "" "$(write_payload "$W/c/src/main.go" s2 | LT_PRELOAD_GATE=warn CLAUDE_PROJECT_DIR="$W/c" bash "$HOOKS/pre-write-validate-preload.sh" 2>/dev/null)" "modo warn nao nega"
assert_eq "" "$(write_payload "$W/c/src/main.go" s2 | LT_PRELOAD_GATE=off CLAUDE_PROJECT_DIR="$W/c" bash "$HOOKS/pre-write-validate-preload.sh" 2>&1)" "LT_PRELOAD_GATE=off desliga"

# ── validate-governance ─────────────────────────────────────────────────────────────────────
describe "post-tool-validate-governance"
post() { local proj="$1"; shift; write_payload "$1" s1 | CLAUDE_PROJECT_DIR="$W/$proj" bash "$HOOKS/post-tool-validate-governance.sh" 2>/dev/null; }
OUT="$(post c "$W/c/AGENTS.md")"
assert_contains "$OUT" '"additionalContext"' "governanca alterada sem registro vira contexto para o agente"
assert_contains "$OUT" "lt-approve exception" "com o caminho de registro"
assert_eq "" "$(post p "$W/p/AGENTS.md")" "repo que nao adotou: silencio"
assert_eq "" "$(post c "$W/c/src/main.go")" "codigo comum: silencio"
mkdir -p "$LT"; printf '%s\texception\tteste\top\tmode=human\n' "$(date +%s)" >> "$LT/approve.log"
assert_eq "" "$(post c "$W/c/AGENTS.md")" "com aprovacao exception fresca: silencio"
B="$W/c/.lt/specs/prd-x"; mkdir -p "$B"; printf '# PRD\n- RF-01 a\n' > "$B/prd.md"
( cd "$W/c" && python3 "$REPO/plugins/lt/lib/sdd.py" approve .lt/specs/prd-x prd >/dev/null )
assert_eq "" "$(post c "$B/prd.md")" "artefato aprovado e intacto: silencio"
printf 'mudou\n' >> "$B/prd.md"
assert_contains "$(post c "$B/prd.md")" "invalidate" "artefato aprovado que mudou pede invalidate"
bash -c 'printf "{}" | CLAUDE_PROJECT_DIR="'"$W/c"'" bash "'"$HOOKS"'/post-tool-validate-governance.sh"' >/dev/null 2>&1
assert_eq "0" "$?" "payload sem arquivo sai 0"

# ── session-end ─────────────────────────────────────────────────────────────────────────────
describe "stop-validate-session-end"
stop() { printf '{"session_id":"s1","stop_hook_active":false}' | CLAUDE_PROJECT_DIR="$W/$1" bash "$HOOKS/stop-validate-session-end.sh" 2>/dev/null; }
printf '# Tasks\n| # | Tarefa | Status | Dependencias | Paralelizavel | Skills |\n|---|---|---|---|---|---|\n| 1.0 | A | done | — | — | — |\n| 2.0 | B | pending | — | — | — |\n' > "$B/tasks.md"
OUT="$(stop c)"
assert_contains "$OUT" '"systemMessage"' "done sem relatorio vira aviso para a pessoa"
assert_contains "$OUT" "1.0" "cita a tarefa"
assert_not_contains "$OUT" "decision" "nunca bloqueia"
printf '# r\nresult_path=.lt/specs/prd-x/nao-existe.json\n' > "$B/1.0_execution_report.md"
assert_contains "$(stop c)" "result_path inexistente" "done com result_path quebrado vira aviso"
printf '{}' > "$B/r.json"; printf '# r\nresult_path=.lt/specs/prd-x/r.json\n' > "$B/1.0_execution_report.md"
assert_eq "" "$(stop c)" "bundle integro: silencio"
assert_eq "" "$(stop p)" "repo que nao adotou: silencio"

# ── subagent-stop-wrapper ───────────────────────────────────────────────────────────────────
describe "subagent-stop-wrapper"
sub() {  # $1=mensagem [$2=agent_type] [$3=stop_hook_active]
  python3 -c 'import json,sys
print(json.dumps({"session_id":"s1","hook_event_name":"SubagentStop","agent_type":sys.argv[2],"stop_hook_active":sys.argv[3]=="1","last_assistant_message":sys.argv[1]}))' \
    "$1" "${2:-lt:task-executor}" "${3:-0}" | CLAUDE_PROJECT_DIR="$W/c" bash "$HOOKS/subagent-stop-wrapper.sh" 2>/dev/null
}
RP=".lt/specs/prd-x/1.0_execution_report.md"
printf '# Relatorio\nconteudo\n' > "$W/c/$RP"
mkdir -p "$B/.checkpoints"
printf '{"status":"done","report_path":"%s","summary":"ok","timestamp":"2026-09-23T00:00:00Z"}' "$RP" > "$B/.checkpoints/1.0.json"
GOOD="$(printf '```yaml\nstatus: done\nreport_path: %s\nsummary: tarefa 1.0 concluida\n```' "$RP")"
assert_eq "" "$(sub "$GOOD")" "envelope valido com relatorio e checkpoint passa"
assert_contains "$(sub "$(printf 'status: done\nreport_path: %s\nsummary: ok\nextra: 1' "$RP")")" '"decision":"block"' "campo extra bloqueia"
assert_contains "$(sub "Pronto! $GOOD")" "texto livre" "texto fora do bloco bloqueia"
assert_contains "$(sub "$(printf 'status: talvez\nreport_path: %s\nsummary: ok' "$RP")")" "status invalido" "status fora do vocabulario bloqueia"
assert_contains "$(sub "$(printf 'status: done\nreport_path: /abs/r.md\nsummary: ok')")" "relativo" "caminho absoluto bloqueia"
assert_contains "$(sub "$(printf 'status: done\nreport_path: .lt/specs/prd-x/2.0_execution_report.md\nsummary: ok')")" "relatorio fisico" "done sem relatorio bloqueia"
assert_eq "" "$(sub "$(printf 'status: blocked\nreport_path: .lt/specs/prd-x/2.0_execution_report.md\nsummary: faltou input')")" "blocked nao exige relatorio fisico"
rm "$B/.checkpoints/1.0.json"
assert_contains "$(sub "$GOOD")" "sem checkpoint" "done sem checkpoint bloqueia"
printf '{"status":"failed","report_path":"%s","summary":"ok","timestamp":"2026-09-23T00:00:00Z"}' "$RP" > "$B/.checkpoints/1.0.json"
assert_contains "$(sub "$GOOD")" "checkpoint diz status" "checkpoint divergente do retorno bloqueia"
assert_eq "" "$(sub "status: x" lt:task-executor 1)" "stop_hook_active libera"
assert_eq "" "$(sub "status: x" lt:reviewer)" "outro subagente nao e' conferido"
BAD_MSG="$(printf 'status: done\nreport_path: /abs\nsummary: s')"
OUT="$(python3 -c 'import json,sys;print(json.dumps({"agent_type":"lt:task-executor","last_assistant_message":sys.argv[1]}))' "$BAD_MSG" \
  | LT_SUBAGENT_CONTRACT=warn CLAUDE_PROJECT_DIR="$W/c" bash "$HOOKS/subagent-stop-wrapper.sh" 2>&1)"
assert_contains "$OUT" "LT_SUBAGENT_CONTRACT=warn" "modo warn avisa"
assert_not_contains "$OUT" '"decision"' "modo warn nao bloqueia"
T="$W/agent.jsonl"
python3 -c 'import json,sys
print(json.dumps({"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"status: done\nreport_path: /x\nsummary: s"}]}}))' > "$T"
OUT="$(python3 -c 'import json,sys;print(json.dumps({"agent_type":"lt:task-executor","agent_transcript_path":sys.argv[1]}))' "$T" | CLAUDE_PROJECT_DIR="$W/c" bash "$HOOKS/subagent-stop-wrapper.sh" 2>/dev/null)"
assert_contains "$OUT" "relativo" "sem last_assistant_message, le o transcript do subagente"
printf 'nao e json' | CLAUDE_PROJECT_DIR="$W/c" bash "$HOOKS/subagent-stop-wrapper.sh" >/dev/null 2>&1
assert_eq "0" "$?" "payload invalido e' erro interno: nao bloqueia"

# ── orcamento de tempo ──────────────────────────────────────────────────────────────────────
describe "todo hook novo cabe no timeout de 5s"
for h in pre-bash-git-operation-gate pre-write-validate-preload post-tool-validate-governance stop-validate-session-end subagent-stop-wrapper; do
  START=$(python3 -c 'import time;print(time.time())')
  write_payload "$W/c/src/main.go" s9 | CLAUDE_PROJECT_DIR="$W/c" bash "$HOOKS/$h.sh" >/dev/null 2>&1
  ELAPSED=$(python3 -c 'import time,sys;print(int((time.time()-float(sys.argv[1]))*1000))' "$START")
  [ "$ELAPSED" -lt 5000 ] && ok "$h: ${ELAPSED}ms" || bad "$h levou ${ELAPSED}ms (timeout do host: 5000)"
done

end_describe
