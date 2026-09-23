#!/usr/bin/env bash
# tests / unit / scripts / approve.test.sh
#
# Casos positivos E negativos da porta unica do audit trail, com HOME isolado.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=../lib/assert.sh
. "$REPO/tests/unit/lib/assert.sh"

export CLAUDE_PLUGIN_ROOT="$REPO/plugins/lt"
export HOME="$(mktemp -d)"
# O perfil segue o HOME isolado: sem isto o teste escreve no audit trail REAL.
export CLAUDE_CONFIG_DIR="$HOME/.claude"
trap 'rm -rf "$HOME"' EXIT
A="$CLAUDE_PLUGIN_ROOT/scripts/approve.sh"
LOG="$HOME/.claude/lt/approve.log"

describe "approve.sh — porta unica do audit trail"
assert_not_scratchpad

# --- positivo: as 8 fases do ciclo em flow ---
for p in analyze-project create-prd create-technical-specification create-tasks \
         execute-task review bugfix refactor; do
  bash "$A" --mode flow "$p" "spec-teste" >/dev/null 2>&1 || bad "fase recusada: $p"
done
assert_eq "8" "$(wc -l < "$LOG" | tr -d ' ')" "8 linhas, uma por estagio do ciclo"
assert_eq "0" "$(awk -F'\t' 'NF!=5' "$LOG" | wc -l | tr -d ' ')" "toda linha com exatamente 5 campos"
assert_eq "8" "$(awk -F'\t' '$5=="mode=flow"' "$LOG" | wc -l | tr -d ' ')" "toda linha com mode=flow"

# --- negativo: bypass em auto e' recusado com exit 3 ---
# "o ciclo autonomo nao assina a propria licenca"
for t in destructive sensitive-read sensitive-write secret-write sensitive-mode-ask allowlist-change; do
  bash "$A" --mode auto "$t" x >/dev/null 2>&1
  assert_eq "3" "$?" "bypass '$t' recusado em --mode auto"
done

# --- positivo: fase em auto continua permitida ---
assert_exit_code 0 bash "$A" --mode auto execute-task "ciclo"

# --- negativo: ataque de substring ---
# Os hooks leem o campo 2 por substring; um slug como este liberaria rm -rf se o token
# fosse aceito por conter "destructive".
bash "$A" --mode human fix-destructive-cleanup x >/dev/null 2>&1
assert_ne "0" "$?" "token que apenas CONTEM 'destructive' e' rejeitado"
assert_eq "0" "$(awk -F'\t' '$2=="fix-destructive-cleanup"' "$LOG" | wc -l | tr -d ' ')" "nada foi gravado para o token invalido"

# --- negativo: TAB no contexto nao desloca colunas ---
bash "$A" --mode human exception "$(printf 'antes\tdepois')" >/dev/null 2>&1
assert_eq "0" "$(awk -F'\t' 'NF!=5' "$LOG" | wc -l | tr -d ' ')" "TAB sanitizado, colunas intactas"
assert_contains "$(tail -1 "$LOG")" "antesdepois" "TAB removido, conteudo preservado"

# --- negativo: modo invalido ---
bash "$A" --mode turbo execute-task x >/dev/null 2>&1
assert_eq "2" "$?" "modo invalido recusado com exit 2"

# --- permissoes ---
assert_eq "600" "$(stat -f '%Lp' "$LOG" 2>/dev/null || stat -c '%a' "$LOG")" "approve.log em 600"

end_describe
