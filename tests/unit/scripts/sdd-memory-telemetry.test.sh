#!/usr/bin/env bash
# tests / unit / scripts / sdd-memory-telemetry.test.sh
#
# Memoria duravel por PRD (append-only, redigida) e leitura da telemetria local (telemetry
# report, metrics). HOME e CLAUDE_CONFIG_DIR isolados: os logs lidos aqui sao os que os hooks
# escrevem no perfil real, e o teste nao pode nem ler nem sujar o perfil de quem roda.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
. "$REPO/tests/unit/lib/assert.sh"

SDD="$REPO/plugins/lt/lib/sdd.py"
W="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$W"' EXIT
export HOME="$W/home" CLAUDE_CONFIG_DIR="$W/home/.claude"
unset LT_HOME
mkdir -p "$CLAUDE_CONFIG_DIR"

describe "isolamento"
assert_not_scratchpad

describe "memory"
git -C "$W" init -q repo
P="$W/repo/.lt/specs/prd-x"
mkdir -p "$P"
mem() { ( cd "$W/repo" && python3 "$SDD" memory .lt/specs/prd-x "$@" 2>&1 ); }
mem_rc() { ( cd "$W/repo" && python3 "$SDD" memory .lt/specs/prd-x "$@" >/dev/null 2>&1 ); }

assert_contains "$(mem list)" "nenhum fato" "memoria vazia e' dita, nao silenciosa"
assert_contains "$(mem add decisao.cache usar TTL de 5 minutos --task 1.0 --session s1)" "gravado" "fato gravado"
F="$P/memory/facts.jsonl"
assert_file_exists "$F" "facts.jsonl criado dentro do bundle"
FAKE_KEY="AKIA""ABCDEFGHIJKLMNOP"
OUT="$(mem add credencial chave de teste "$FAKE_KEY")"
assert_contains "$OUT" "redigido" "segredo e' redigido antes de gravar"
assert_not_contains "$(cat "$F")" "$FAKE_KEY" "o segredo nunca chega ao disco"
LINES_BEFORE="$(wc -l < "$F" | tr -d ' ')"
FIRST_LINE="$(head -1 "$F")"
assert_contains "$(mem add decisao.cache usar TTL de 10 minutos)" "substitui" "mesma chave com conteudo novo substitui"
assert_eq "$((LINES_BEFORE + 1))" "$(wc -l < "$F" | tr -d ' ')" "append-only: nada e' reescrito"
assert_eq "$FIRST_LINE" "$(head -1 "$F")" "a versao anterior continua no arquivo"
LIST="$(mem list)"
assert_contains "$LIST" "10 minutos" "list mostra a versao ativa"
assert_not_contains "$LIST" "5 minutos" "list nao mostra a substituida"
assert_contains "$LIST" "[2 versoes]" "list diz que houve versao anterior"
SHOW="$(mem show decisao.cache)"
assert_contains "$SHOW" "v1 [substituida]" "show traz o historico"
assert_contains "$SHOW" "sessao=s1 tarefa=1.0" "com a origem"
assert_exit_code 2 mem_rc add 'Chave Ruim' texto
assert_exit_code 2 mem_rc add ok.key texto --task abc
assert_exit_code 1 mem_rc show inexistente

describe "telemetry report"
LT="$CLAUDE_CONFIG_DIR/lt"
tel() { python3 "$SDD" telemetry report "$@" 2>&1; }
assert_contains "$(tel)" "sem dados (telemetry.jsonl ausente" "log ausente nao vira zero"
mkdir -p "$LT"
TODAY="$(date -u +%Y-%m-%d)"
{
  for i in 1 2 3; do printf '{"ts":"%sT00:00:00+00:00","day":"%s","kind":"skill.fire","tool":"Skill","session":"s%s","skill":"lt:review"}\n' "$TODAY" "$TODAY" "$i"; done
  printf '{"ts":"%sT00:00:00+00:00","day":"%s","kind":"skill.fire","tool":"Skill","session":"s1","skill":"lt:execute-task"}\n' "$TODAY" "$TODAY"
  printf '{"ts":"2001-01-01T00:00:00+00:00","day":"2001-01-01","kind":"skill.fire","session":"old","skill":"lt:antigo"}\n'
  printf 'isto nao e json\n'
} > "$LT/telemetry.jsonl"
printf '{"ts":"%sT00:00:00+00:00","day":"%s","kind":"tool.cost","input_tokens":100,"output_tokens":50,"cache_read_input_tokens":800,"cache_creation_input_tokens":100,"model":"m1","message_id":"a"}\n' "$TODAY" "$TODAY" > "$LT/cost-daily.jsonl"
OUT="$(tel)"
assert_contains "$OUT" "disparos de skill: 4 em 3 sessao" "conta disparos e sessoes da janela"
assert_contains "$OUT" "1. lt:review" "top skill primeiro"
assert_not_contains "$OUT" "lt:antigo" "fora da janela nao entra"
assert_contains "$OUT" "tokens: 1050 total" "soma os tokens do transcript"
assert_contains "$OUT" "cache hit: 80.0%" "razao de cache calculada"
assert_contains "$OUT" "1 linha(s) malformada" "linha ruim e' contada, nao escondida"
python3 "$SDD" telemetry report --budget 2000 >/dev/null 2>&1
assert_eq "0" "$?" "abaixo do orcamento sai 0"
assert_contains "$(tel --budget 1000)" "ORCAMENTO ESTOURADO" "acima do orcamento e' anunciado"
python3 "$SDD" telemetry report --budget 1000 >/dev/null 2>&1
assert_eq "1" "$?" "acima do orcamento sai 1"
JSON="$(python3 "$SDD" telemetry report --json)"
assert_eq "4" "$(printf '%s' "$JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin)["skill_fires"])')" "--json expoe o mesmo numero"
LT_HOME="$W/outro" python3 "$SDD" telemetry report 2>&1 | grep -q "sem dados" && ok "LT_HOME sobrepoe o perfil" || bad "LT_HOME ignorado"

describe "metrics"
mkdir -p "$W/repo/.lt/audit"
printf '%sT00:00:00Z | hook=pre-bash-block-destructive | status=BLOCKED | x\n%sT00:00:00Z | hook=pre-bash-block-destructive | status=BLOCKED | y\n' "$TODAY" "$TODAY" > "$W/repo/.lt/audit/hook-fires.log"
printf '%s\tdestructive\tctx\top\tmode=human\n' "$(date +%s)" > "$LT/approve.log"
OUT="$( cd "$W/repo" && python3 "$SDD" metrics 2>&1 )"
assert_contains "$OUT" "pre-bash-block-destructive" "le as decisoes de hook do audit do repo"
assert_contains "$OUT" "destructive=1" "le as aprovacoes"
assert_contains "$OUT" "tokens no periodo: 1050" "reaproveita a telemetria de custo"
assert_contains "$OUT" "execute-task" "estima o contexto estatico das skills"

end_describe
