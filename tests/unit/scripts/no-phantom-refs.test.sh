#!/usr/bin/env bash
# tests / unit / scripts / no-phantom-refs.test.sh
#
# Guarda contra a classe de defeito mais cara deste harness: PROMETER O QUE NAO EXISTE.
#
# Ja apareceu tres vezes:
#   1. uma skill anunciava um linter e references que nao estavam no diretorio;
#   2. o index.md do repo de conhecimento listava 10 componentes inexistentes e 4 links mortos;
#   3. este proprio repo: uma skill roteava para comandos que nao existiam, e o SessionStart
#      apontava para um script ausente.
#
# O sintoma e' sempre o mesmo e sempre silencioso: o agente le uma instrucao plausivel, tenta
# abrir o alvo, nao encontra e improvisa.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
. "$REPO/tests/unit/lib/assert.sh"
cd "$REPO"

describe "nenhuma referencia fantasma"

# 1. Todo lt:<nome> citado na prosa existe em commands/, e' uma skill instalada OU um subagente
#    do plugin (agents/<nome>.md — o host os expoe como `lt:<nome>`, ex.: `lt:task-executor`).
DEFERRED_FILE="config/deferred-components.txt"
is_deferred() {
  [ -r "$DEFERRED_FILE" ] || return 1
  grep -qE "^$1[[:space:]]*\\|" "$DEFERRED_FILE"
}

MISSING=""
STILL_DEFERRED=""
for ref in $(grep -rhoE --binary-files=without-match 'lt:[a-z0-9][a-z0-9-]+' \
             plugins/lt/skills plugins/lt/commands plugins/lt/config docs ./*.md 2>/dev/null | sort -u); do
  name="${ref#lt:}"
  case "$name" in generated-*|generated) continue ;; esac
  [ -f "plugins/lt/commands/$name.md" ] && continue
  [ -f "plugins/lt/skills/$name/SKILL.md" ] && continue
  [ -f "plugins/lt/agents/$name.md" ] && continue
  if is_deferred "$name"; then STILL_DEFERRED="$STILL_DEFERRED $name"; continue; fi
  MISSING="$MISSING $name"
done
if [ -n "$MISSING" ]; then
  bad "componentes lt:<nome> citados, inexistentes e NAO declarados em $DEFERRED_FILE:$MISSING"
else
  ok "todo lt:<nome> citado resolve, ou esta declarado como adiado"
fi

# Caducidade: nome declarado como adiado que PASSOU a existir virou mentira e tem de sair.
LIAR=""
while IFS='|' read -r n _rest; do
  n="$(printf '%s' "$n" | tr -d ' ')"
  case "$n" in ''|\#*) continue ;; esac
  if [ -f "plugins/lt/skills/$n/SKILL.md" ] || [ -f "plugins/lt/commands/$n.md" ] || [ -f "plugins/lt/agents/$n.md" ]; then
    LIAR="$LIAR $n"
  fi
done < "$DEFERRED_FILE"
if [ -n "$LIAR" ]; then
  bad "declarado como adiado mas JA EXISTE (remova de $DEFERRED_FILE):$LIAR"
else
  ok "nenhuma entrada caduca na lista de adiados"
fi

# Toda skill que cita a camada adiada tem de carregar a nota de condicionalidade.
NONOTE=""
for f in $(grep -rl --binary-files=without-match 'lt:go-implementation\|lt:node-implementation\|lt:python-implementation\|lt:dotnet-csharp-implementation' \
           plugins/lt/skills --include='*.md' 2>/dev/null); do
  case "$f" in */assets/*) continue ;; esac
  grep -q 'Camada de linguagem é opcional' "$f" || NONOTE="$NONOTE $(basename "$(dirname "$f")")"
done
if [ -n "$NONOTE" ]; then
  bad "cita a camada adiada sem a nota de condicionalidade:$NONOTE"
else
  ok "toda skill que cita a camada adiada explica que ela pode nao existir"
fi

# 2. Todo command referenciado em hooks.json resolve em disco.
BADH=0
for c in $(python3 -c "
import json
d=json.load(open('plugins/lt/hooks/hooks.json'))
for ev in d['hooks'].values():
    for grp in ev:
        for h in grp['hooks']:
            print(h['command'].strip('\"'))"); do
  p="${c#\"}"; p="${p%\"}"; p="${p/\$\{CLAUDE_PLUGIN_ROOT\}/plugins/lt}"
  p="$(printf '%s' "$c" | sed 's|"||g; s|${CLAUDE_PLUGIN_ROOT}|plugins/lt|')"
  [ -f "$p" ] || { bad "hooks.json referencia arquivo ausente: $p"; BADH=1; }
done
[ "$BADH" -eq 0 ] && ok "todo command do hooks.json resolve em disco"

# 3. Todo script citado no .claude/settings.json do proprio repo existe.
if [ -f .claude/settings.json ]; then
  BADS=0
  for s in $(python3 -c "
import json,re
d=json.load(open('.claude/settings.json'))
for ev in d.get('hooks',{}).values():
    for grp in ev:
        for h in grp.get('hooks',[]):
            m=re.search(r'\\\$CLAUDE_PROJECT_DIR/([A-Za-z0-9_./-]+)', h.get('command',''))
            if m: print(m.group(1))"); do
    [ -f "$s" ] || { bad ".claude/settings.json referencia script ausente: $s"; BADS=1; }
  done
  [ "$BADS" -eq 0 ] && ok "todo script do SessionStart deste repo existe"
fi

# 4. Todo ${CLAUDE_SKILL_DIR}/<algo> citado numa skill resolve.
BADK=0
for rel in $(grep -rhoE '\$\{CLAUDE_SKILL_DIR\}/[A-Za-z0-9_./-]+' plugins/lt/skills --include='*.md' 2>/dev/null \
             | sed 's|${CLAUDE_SKILL_DIR}/||' | sort -u); do
  case "$rel" in
    ../*) [ -f "plugins/lt/skills/${rel#../}" ] || { bad "script prometido e ausente (cruzado): $rel"; BADK=1; } ;;
    *) find plugins/lt/skills -path "*/$rel" -print -quit 2>/dev/null | grep -q . \
         || { bad "script prometido e ausente: $rel"; BADK=1; } ;;
  esac
done
[ "$BADK" -eq 0 ] && ok "todo script prometido por skill resolve em disco"

# 5. Nenhum caminho da distribuicao antiga sobreviveu.
if grep -rq '~/\.claude/skills\|\$HOME/\.claude/skills' plugins/lt/skills --include='*.md' 2>/dev/null; then
  bad "skill ainda cita o caminho do symlink legado"
else
  ok "nenhuma skill cita ~/.claude/skills"
fi

end_describe
