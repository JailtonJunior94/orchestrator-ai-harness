#!/usr/bin/env bash
# tests / e2e / run.sh — banner de sucesso: E2E PASSOU
#
# Exercita o harness como o host o exercita: alimentando hooks com payload real e caminhando o
# ciclo SDD inteiro num sandbox descartavel.
#
# TUDO RODA COM HOME E CLAUDE_CONFIG_DIR ISOLADOS. Esta regra foi paga: um teste com HOME
# isolado mas CLAUDE_CONFIG_DIR apontando para o perfil real escreveu dez linhas falsas no
# approve.log de producao — e passou verde, porque as linhas que ele mesmo criou satisfaziam
# as proprias asserções.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
export HOME="$SANDBOX/home"
export CLAUDE_CONFIG_DIR="$HOME/.claude"
mkdir -p "$CLAUDE_CONFIG_DIR"
export CLAUDE_PLUGIN_ROOT="$REPO/plugins/lt"

if [ -t 1 ]; then C_OK=$'\033[32m'; C_BAD=$'\033[31m'; C_OFF=$'\033[0m'
else C_OK=""; C_BAD=""; C_OFF=""; fi
OK=0; BAD=0
ok()  { OK=$((OK+1));  printf '  %s✓%s %s\n' "$C_OK" "$C_OFF" "$1"; }
bad() { BAD=$((BAD+1)); printf '  %s✗%s %s\n' "$C_BAD" "$C_OFF" "$1" >&2; }
sec() { printf '\n▸ %s\n' "$1"; }

H="$CLAUDE_PLUGIN_ROOT/hooks"

# hook <descricao> <json> <script> <esperado: passa|BLOQUEIA|ask>
hook() {
  printf '%s' "$2" | bash "$3" >"$SANDBOX/o" 2>"$SANDBOX/e"; rc=$?
  if [ -s "$SANDBOX/o" ]; then got=ask; elif [ "$rc" -eq 2 ]; then got=BLOQUEIA; else got=passa; fi
  [ "$got" = "$4" ] && ok "$1 -> $got" || bad "$1 -> esperado $4, obtido $got"
}

# ── guardas de seguranca ─────────────────────────────────────────────────────────────────────
sec "hooks de seguranca, com payload do host"
hook "rm -rf /"                '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}'                        "$H/pre-bash-block-destructive.sh"       BLOQUEIA
hook "ls -la"                  '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'                          "$H/pre-bash-block-destructive.sh"       passa
hook "terraform destroy"       '{"tool_name":"Bash","tool_input":{"command":"terraform destroy"}}'               "$H/pre-bash-block-destructive.sh"       BLOQUEIA
hook "cat ~/.ssh/id_rsa"       '{"tool_name":"Bash","tool_input":{"command":"cat ~/.ssh/id_rsa"}}'               "$H/pre-bash-block-sensitive-paths.sh"   BLOQUEIA
hook "npm install"             '{"tool_name":"Bash","tool_input":{"command":"npm install"}}'                     "$H/pre-bash-block-sensitive-paths.sh"   passa
hook "escrever .env"           '{"tool_name":"Write","tool_input":{"file_path":"api/.env"}}'                     "$H/pre-write-block-sensitive-paths.sh"  BLOQUEIA
hook "escrever src/a.ts"       '{"tool_name":"Write","tool_input":{"file_path":"src/a.ts"}}'                     "$H/pre-write-block-sensitive-paths.sh"  passa
hook "editar Dockerfile"       '{"tool_name":"Edit","tool_input":{"file_path":"Dockerfile"}}'                    "$H/pre-write-block-sensitive-paths.sh"  ask
hook "DSN com senha"           '{"tool_name":"Write","tool_input":{"file_path":"c.ts","content":"postgresql://u:p4ssw0rd@db.prod:5432/x"}}' "$H/pre-write-scan-secrets.sh" ask
hook "codigo limpo"            '{"tool_name":"Write","tool_input":{"file_path":"c.ts","content":"export const a=1"}}'                       "$H/pre-write-scan-secrets.sh" passa
hook "token do Appsmith"       '{"tool_name":"Write","tool_input":{"file_path":"d.sh","content":"curl https://x/y?auth=abcdefghij0123456789KL"}}' "$H/pre-write-scan-secrets.sh" ask

# ── dial guided ──────────────────────────────────────────────────────────────────────────────
sec "dial guided (unico hook de PROCESSO)"
P='{"tool_name":"Write","tool_input":{"file_path":"src/x.ts"},"session_id":"e2e"}'
printf '%s' "$P" | bash "$H/pre-write-spec-coverage-warn.sh" >/dev/null 2>&1
[ $? -eq 0 ] && ok "guided=off nao interrompe" || bad "guided=off interrompeu"
printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"src/y.ts"},"session_id":"e2e2"}' \
  | LT_GUIDED=strict bash "$H/pre-write-spec-coverage-warn.sh" >/dev/null 2>&1
[ $? -eq 2 ] && ok "guided=strict bloqueia codigo sem spec" || bad "guided=strict nao bloqueou"
printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"docs/z.md"},"session_id":"e2e3"}' \
  | LT_GUIDED=strict bash "$H/pre-write-spec-coverage-warn.sh" >/dev/null 2>&1
[ $? -eq 0 ] && ok "guided=strict NAO gateia prosa" || bad "guided=strict gateou prosa"

# ── audit trail: ciclo completo ──────────────────────────────────────────────────────────────
sec "audit trail — as 8 fases do ciclo em --mode flow"
A="$CLAUDE_PLUGIN_ROOT/scripts/approve.sh"
for p in analyze-project create-prd create-technical-specification create-tasks \
         execute-task review bugfix refactor; do
  bash "$A" --mode flow "$p" "e2e" >/dev/null 2>&1 || bad "fase recusada: $p"
done
LOG="$CLAUDE_CONFIG_DIR/lt/approve.log"
[ "$(wc -l < "$LOG" | tr -d ' ')" = "8" ] && ok "8 linhas, uma por estagio" || bad "esperado 8 linhas"
[ "$(awk -F'\t' 'NF!=5' "$LOG" | wc -l | tr -d ' ')" = "0" ] && ok "toda linha com 5 campos" || bad "linha fora do formato"
[ "$(awk -F'\t' '$5=="mode=flow"' "$LOG" | wc -l | tr -d ' ')" = "8" ] && ok "toda linha com mode=flow" || bad "mode divergente"

sec "audit trail — negativos"
for t in destructive secret-write sensitive-write allowlist-change; do
  bash "$A" --mode auto "$t" x >/dev/null 2>&1
  [ $? -eq 3 ] && ok "bypass '$t' recusado em auto (exit 3)" || bad "bypass '$t' passou em auto"
done
bash "$A" --mode human fix-destructive-cleanup x >/dev/null 2>&1
[ $? -ne 0 ] && ok "token por substring rejeitado" || bad "substring abriu a guarda"

# ── ciclo SDD num repo de verdade ────────────────────────────────────────────────────────────
sec "ciclo SDD — spec ancorada no repo onde o comando roda"
PROJ="$SANDBOX/projeto-x"; mkdir -p "$PROJ/src"; ( cd "$PROJ" && git init -q )
SDD="$CLAUDE_PLUGIN_ROOT/scripts/lt-sdd.sh"
ROOT="$(cd "$PROJ/src" && env -u CLAUDE_PROJECT_DIR -u LT_PROJECT_DIR bash "$SDD" specs-root)"
# realpath e' obrigatorio na comparacao: no macOS /var e' symlink para /private/var, entao o
# caminho que o harness devolve nao casa textualmente com o que o teste montou.
PROJ_REAL="$(python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$PROJ")"
[ "$ROOT" = "$PROJ_REAL/.lt/specs" ] \
  && ok "specs-root ancora na raiz do repo, rodando de src/" \
  || bad "specs-root errado: $ROOT (esperado $PROJ_REAL/.lt/specs)"

P="$PROJ/.lt/specs/prd-exemplo"; mkdir -p "$P"
printf '# PRD\n## Requisitos Funcionais\n- RF-01: exemplo.\n' > "$P/prd.md"
printf '<!-- spec-hash-prd: %s -->\n# TechSpec\n' "$(printf '0%.0s' $(seq 64))" > "$P/techspec.md"
cat > "$P/tasks.md" <<'EOT'
<!-- spec-hash-prd: 0000000000000000000000000000000000000000000000000000000000000000 -->
<!-- spec-hash-techspec: 0000000000000000000000000000000000000000000000000000000000000000 -->
## Tarefas
| # | Título | Status | Dependências | Paralelizável | Skills |
|---|--------|--------|-------------|---------------|--------|
| 1.0 | Implementar | pending | — | — | — |
## Cobertura de Requisitos
| Tarefa | Requisitos cobertos |
|--------|-------------------|
| 1.0 | RF-01 |
EOT

cd "$PROJ"
bash "$SDD" check-spec-drift "$P" >/dev/null 2>&1
[ $? -eq 1 ] && ok "drift detectado com hash placeholder" || bad "drift nao detectado"
bash "$SDD" sync-spec-hash "$P" >/dev/null 2>&1 && ok "sync-spec-hash" || bad "sync falhou"
bash "$SDD" check-spec-drift "$P" >/dev/null 2>&1 && ok "sem drift apos sync" || bad "drift persistiu"
bash "$SDD" validate-sdd "$P" >/dev/null 2>&1 && ok "validate-sdd" || bad "validate-sdd falhou"

bash "$SDD" approve "$P" tasks >/dev/null 2>&1
[ $? -eq 3 ] && ok "aprovar tasks antes do prd e' RECUSADO" || bad "ordem do ciclo nao foi cobrada"
bash "$SDD" approve "$P" prd >/dev/null 2>&1 && bash "$SDD" approve "$P" techspec >/dev/null 2>&1 \
  && bash "$SDD" approve "$P" tasks >/dev/null 2>&1 && ok "ordem correta aprovada" || bad "aprovacao em ordem falhou"
bash "$SDD" approve "$P" prd >/dev/null 2>&1
[ $? -eq 3 ] && ok "reaprovar sem mudanca e' RECUSADO" || bad "reaprovacao passou"

printf -- '- RF-02: novo.\n' >> "$P/prd.md"
bash "$SDD" sync-spec-hash "$P" >/dev/null 2>&1
[ $? -eq 3 ] && ok "sync sobre aprovado sujo e' RECUSADO (nao mascara drift)" || bad "sync mascarou drift"
bash "$SDD" invalidate "$P" --from prd >/dev/null 2>&1 && ok "invalidate propaga stale" || bad "invalidate falhou"

sec "contrato de evidencia — fail-closed"
cat > "$P/1.0_execution_report.md" <<'EOT'
## Tarefa
1.0
## Comandos Executados
pytest
## Arquivos Alterados
src/a.py
## Resultados de Validação
12 passed
## Critérios de Aceite
- Criterio sem prova
EOT
bash "$SDD" seal-evidence "$P/1.0_execution_report.md" >/dev/null 2>&1
[ $? -eq 1 ] && ok "criterio sem prova e' REJEITADO" || bad "criterio sem prova passou"
python3 - "$P/1.0_execution_report.md" <<'PYEOF'
import io,sys
p=sys.argv[1]; s=io.open(p,encoding="utf-8").read()
io.open(p,"w",encoding="utf-8").write(s.replace("- Criterio sem prova","- Criterio atendido -> comprovado: saida do pytest"))
PYEOF
bash "$SDD" seal-evidence "$P/1.0_execution_report.md" >/dev/null 2>&1 && ok "criterio com prova e' aceito" || bad "criterio com prova rejeitado"

sec "isolamento entre repos"
PROJ2="$SANDBOX/projeto-y"; mkdir -p "$PROJ2"; ( cd "$PROJ2" && git init -q )
( cd "$PROJ2" && env -u CLAUDE_PROJECT_DIR -u LT_PROJECT_DIR bash "$SDD" state "$P" ) >/dev/null 2>&1
[ $? -eq 3 ] && ok "spec do repo A e' RECUSADA de dentro do repo B" || bad "spec cruzou de repo"

printf '\n───────────────────────────────\n'
printf '%d ok · %d falha\n' "$OK" "$BAD"
if [ "$BAD" -eq 0 ]; then printf 'E2E PASSOU\n'; exit 0; fi
printf 'E2E FALHOU\n' >&2; exit 1
