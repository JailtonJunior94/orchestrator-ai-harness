#!/usr/bin/env bash
# tests / unit / scripts / specs-root-cascade.test.sh
#
# A raiz de specs precisa ser a MESMA para o motor SDD e para os hooks do ciclo, em qualquer
# checkout do mesmo repositorio.
#
# Estes casos existem porque o harness passou por um periodo com DOIS defaults: `lib/sdd.py`
# resolvia `.lt/specs` e os hooks do ciclo faziam `${AI_TASKS_ROOT:-.specs}`. Num repo sem
# `.specs/`, o motor gravava a spec num lugar e os hooks procuravam noutro — e o sintoma so
# aparecia na execucao da tarefa, como "tasks.md nao existe" num caminho que ninguem tinha
# pedido. Todas as suites estavam verdes durante esse periodo inteiro.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
. "$REPO/tests/unit/lib/assert.sh"

SDD="$REPO/plugins/lt/lib/sdd.py"
PLUGIN="$REPO/plugins/lt"
# realpath: no macOS `mktemp -d` devolve /var/..., que e' symlink para /private/var/...
# O motor canoniza; comparar sem canonizar aqui produziria falha por symlink, nao por bug.
W="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$W"' EXIT

# Sem heranca do ambiente da sessao: LT_/AI_/CLAUDE_ definidos por fora mascarariam a cascata.
run_specs_root() {
  ( cd "$1" && env -u CLAUDE_PROJECT_DIR -u LT_PROJECT_DIR -u LT_TASKS_ROOT -u AI_TASKS_ROOT \
      python3 "$SDD" specs-root )
}

describe "cascata do specs-root"

# --- default do harness -----------------------------------------------------------------
mkdir -p "$W/plain" && ( cd "$W/plain" && git init -q )
assert_eq "$(run_specs_root "$W/plain")" "$W/plain/.lt/specs" \
  "repo limpo cai no padrao .lt/specs"

# --- `.specs/` existente em disco -------------------------------------------------------
mkdir -p "$W/legacy/.specs" && ( cd "$W/legacy" && git init -q )
assert_eq "$(run_specs_root "$W/legacy")" "$W/legacy/.specs" \
  ".specs/ existente em disco vence o padrao"

# --- `.specs/` versionado mas AUSENTE deste checkout ------------------------------------
# O caso do worktree novo: `isdir` responde pelo checkout, nao pelo repositorio.
mkdir -p "$W/tracked/.specs" && ( cd "$W/tracked" && git init -q )
echo placeholder > "$W/tracked/.specs/.gitkeep"
( cd "$W/tracked" && git add .specs/.gitkeep >/dev/null 2>&1 )
rm -rf "$W/tracked/.specs"
assert_eq "$(run_specs_root "$W/tracked")" "$W/tracked/.specs" \
  ".specs/ versionado no git vence mesmo sem existir no checkout"

# --- config do repo -----------------------------------------------------------------------
# O unico sinal deterministico quando o repo usa .specs/ sem versiona-lo.
mkdir -p "$W/cfg/.lt" && ( cd "$W/cfg" && git init -q )
printf 'tasks_root: .specs\n' > "$W/cfg/.lt/config.yaml"
assert_eq "$(run_specs_root "$W/cfg")" "$W/cfg/.specs" \
  "tasks_root do .lt/config.yaml vence o padrao"

mkdir -p "$W/cfg2/.claude" && ( cd "$W/cfg2" && git init -q )
printf '# comentario\ntasks_root: "docs/specs"   # inline\n' > "$W/cfg2/.claude/config.yaml"
assert_eq "$(run_specs_root "$W/cfg2")" "$W/cfg2/docs/specs" \
  "tasks_root aceita aspas e comentario inline"

# --- precedencia do env sobre o config ---------------------------------------------------
GOT="$( cd "$W/cfg" && env -u CLAUDE_PROJECT_DIR -u LT_PROJECT_DIR -u AI_TASKS_ROOT \
        LT_TASKS_ROOT=outro python3 "$SDD" specs-root )"
assert_eq "$GOT" "$W/cfg/outro" "LT_TASKS_ROOT vence o config"

GOT="$( cd "$W/cfg" && env -u CLAUDE_PROJECT_DIR -u LT_PROJECT_DIR -u LT_TASKS_ROOT \
        AI_TASKS_ROOT=herdado python3 "$SDD" specs-root )"
assert_eq "$GOT" "$W/cfg/herdado" "AI_TASKS_ROOT tambem e' honrado (nome herdado)"

# --- config quebrado nao derruba o ciclo -------------------------------------------------
mkdir -p "$W/broken/.lt" && ( cd "$W/broken" && git init -q )
printf 'isto: [nao\n  e: yaml valido\n' > "$W/broken/.lt/config.yaml"
assert_eq "$(run_specs_root "$W/broken")" "$W/broken/.lt/specs" \
  "config sem tasks_root nao opina — cai no padrao, nao em erro"

describe "hooks do ciclo resolvem a MESMA raiz que o motor"

# O bug original: os hooks nunca perguntavam ao motor. Este caso quebra se alguem reintroduzir
# um default local em qualquer um deles.
for hook in pre-execute-all-tasks.sh post-execute-task.sh post-wave.sh; do
  if grep -q 'AI_TASKS_ROOT:-' "$PLUGIN/scripts/cycle/$hook" 2>/dev/null; then
    bad "$hook voltou a hardcodar um default de specs-root"
  else
    ok "$hook nao hardcoda default"
  fi
done

. "$PLUGIN/lib/specs-root.sh"
GOT="$(CLAUDE_PLUGIN_ROOT="$PLUGIN" lt_specs_root "$W/cfg" 2>/dev/null)"
assert_eq "$GOT" "$W/cfg/.specs" "lt_specs_root (shell) concorda com o motor (python)"

end_describe
