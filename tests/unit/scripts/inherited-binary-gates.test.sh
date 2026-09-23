#!/usr/bin/env bash
# tests / unit / scripts / inherited-binary-gates.test.sh
#
# Gate que reprova SEMPRE e' pior que gate ausente: ele parece governanca e e' so uma parede.
#
# O harness de origem instalava um binario. Este plugin decidiu nao instalar nenhum — o motor
# SDD e' `lib/sdd.py`. Sobraram gates checando esse binario, e um rename global os corrompeu:
#
#   - `command -v harness lt` — dois argumentos, nenhum deles um comando existente. Reprovava em
#     toda maquina limpa. Em `execute-task` isso significava parar com `needs_input` SEMPRE.
#   - `AI_SPEC_BIN="${AI_SPEC_BIN:-harness lt}"` — default e' uma string com espaco, que nao e'
#     nome de comando valido. Toda tarefa com status=done reprovava no post-hook.
#   - `! bash lt-sdd.sh` sem subcomando — o dispatcher sai 2 (uso invalido), entao a negacao era
#     verdadeira sempre.
#
# Nenhuma suite pegava nada disso: elas verificavam presenca de arquivo, nao comportamento.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
. "$REPO/tests/unit/lib/assert.sh"

PLUGIN="$REPO/plugins/lt"
SELF="$HERE/$(basename "${BASH_SOURCE[0]}")"

# Este arquivo cita os padroes proibidos para explica-los, e o proprio plugin documenta em
# comentario o defeito que corrigiu. Comentario e citacao em markdown sao DOCUMENTACAO do
# defeito, nao o defeito: um guard que nao distingue os dois reprova justamente o texto que
# explica a correcao — foi assim que tres guards deste harness nasceram quebrados, cada um
# casando com a propria prosa.
scan() {
  grep -rn --binary-files=without-match "$1" "$PLUGIN" 2>/dev/null \
    | grep -v "^$SELF:" \
    | grep -vE ':[0-9]+:[[:space:]]*#' \
    | grep -vE ':[0-9]+:[[:space:]]*>'
}

describe "gates nao dependem de binario que o plugin nao distribui"

HITS="$(scan 'command -v harness')"
if [ -n "$HITS" ]; then
  bad "ainda existe 'command -v harness': $(printf '%s' "$HITS" | head -1)"
else
  ok "nenhum 'command -v harness'"
fi

HITS="$(scan 'AI_SPEC_BIN:-[^}]')"
if [ -n "$HITS" ]; then
  bad "AI_SPEC_BIN voltou a ter default: $(printf '%s' "$HITS" | head -1)"
else
  ok "AI_SPEC_BIN sem default — delegacao externa e' opt-in"
fi

# `go build` / `go run` do harness de origem: instrucao que o consumidor nao tem como seguir.
HITS="$(scan 'go build -o \./harness')"
if [ -n "$HITS" ]; then
  bad "instrucao de build do binario de origem ainda presente"
else
  ok "sem instrucao de build de binario externo"
fi

describe "dispatcher sem subcomando sai 2 — negacao disso nao serve como gate"

bash "$PLUGIN/scripts/lt-sdd.sh" >/dev/null 2>&1
RC=$?
assert_eq "$RC" "2" "lt-sdd.sh sem argumento sai 2 (uso invalido)"

HITS="$(grep -rn '! bash "\${CLAUDE_PLUGIN_ROOT}/scripts/lt-sdd.sh" >' "$PLUGIN/skills" 2>/dev/null)"
if [ -n "$HITS" ]; then
  bad "skill usa a negacao de 'lt-sdd.sh' sem subcomando como gate: $(printf '%s' "$HITS" | head -1)"
else
  ok "nenhuma skill usa essa negacao como gate"
fi

describe "integridade textual do plugin"

# Mojibake: UTF-8 lido como latin-1 e regravado. Estava commitado em 3 arquivos, invisivel
# para toda suite, e chegava ao agente como prosa ilegivel.
HITS="$(grep -rln --binary-files=without-match 'Ã§\|Ã£\|Ãµ\|Ã©\|Ã­\|Ã³\|Ãª\|Ã¡\|Ãº' "$PLUGIN" 2>/dev/null | grep -v "^$SELF$")"
if [ -n "$HITS" ]; then
  bad "mojibake em: $(printf '%s' "$HITS" | head -3 | tr '\n' ' ')"
else
  ok "sem mojibake"
fi

# Caminho corrompido por rename global: `.agents/skills/` virou prosa colada no identificador,
# produzindo caminhos como "$AGENTS_ROOT/skills do plugin lt$skill".
HITS="$(grep -rn --binary-files=without-match 'skills do plugin lt[$<`]' "$PLUGIN" 2>/dev/null | grep -v "^$SELF:")"
if [ -n "$HITS" ]; then
  bad "caminho corrompido por rename: $(printf '%s' "$HITS" | head -1)"
else
  ok "nenhum caminho corrompido por rename"
fi

# Cascata com entradas vazias — outra sobra do mesmo rename.
HITS="$(grep -rn --binary-files=without-match '→ `` →' "$PLUGIN" 2>/dev/null | grep -v "^$SELF:")"
if [ -n "$HITS" ]; then
  bad "cascata com caminho vazio: $(printf '%s' "$HITS" | head -1)"
else
  ok "nenhuma cascata com caminho vazio"
fi

end_describe
