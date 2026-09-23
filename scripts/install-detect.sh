#!/usr/bin/env bash
# orchestrator-ai-harness / scripts / install-detect.sh
#
# SessionStart do PROPRIO repositorio do harness. E' isto que faz o repo se auto-diagnosticar
# quando alguem o abre no Claude Code.
#
# CONTRATO: exit 0 SEMPRE, e silencio quando esta tudo em dia.
# Um hook de contexto que falha a sessao transforma um detalhe em impedimento de trabalho. E um
# banner que aparece em toda sessao vira ruido — as pessoas param de ler, inclusive quando ele
# tem algo importante a dizer.
#
# Cinco estados por plugin canonico:
#   installed  cache + registro + habilitado + versao do cache == manifesto  -> silencio
#   missing    sem entrada no registro                                       -> oferecer install
#   outdated   cache < manifesto (comparacao SEMANTICA)                      -> oferecer update
#   orphaned   registro aponta para installPath inexistente                  -> oferecer install
#   shadowed   symlink legado convive com o plugin                           -> oferecer migracao
#
# `shadowed` e' o quinto estado, que o harness de referencia nao tem: aqui existe uma
# distribuicao anterior por symlink, e duas fontes da mesma skill e' um erro que nao da erro.

set -uo pipefail

REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LT_CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
MKT="lt"
CANONICAL="lt"

MANIFEST="$REPO_ROOT/.claude-plugin/marketplace.json"
[ -r "$MANIFEST" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

REG="$LT_CFG/plugins/installed_plugins.json"
SET="$LT_CFG/settings.json"

emit() {  # additionalContext para o agente
  printf '%s\n' "$1"
  exit 0
}

for p in $CANONICAL; do
  WANT="$(python3 -c "
import json,sys
m=json.load(open('$MANIFEST'))
v=[x['version'] for x in m.get('plugins',[]) if x['name']=='$p']
print(v[0] if v else '')" 2>/dev/null)"
  [ -n "$WANT" ] || continue

  INSTALL_PATH="$(python3 -c "
import json,os
try:
    d=json.load(open('$REG'))
except Exception:
    print(''); raise SystemExit
e=d.get('plugins',{}).get('$p@$MKT') or []
print(e[0].get('installPath','') if e else '')" 2>/dev/null)"

  ENABLED="$(python3 -c "
import json
try:
    d=json.load(open('$SET'))
except Exception:
    print('no'); raise SystemExit
print('yes' if d.get('enabledPlugins',{}).get('$p@$MKT') is True else 'no')" 2>/dev/null)"

  if [ -z "$INSTALL_PATH" ]; then
    emit "O harness LT nao esta instalado neste perfil ($LT_CFG). Ofereca rodar: bash scripts/install.sh --config-dir \"$LT_CFG\""
  fi

  if [ ! -d "$INSTALL_PATH" ]; then
    emit "O harness LT esta registrado mas o caminho de instalacao sumiu ($INSTALL_PATH). Ofereca rodar: bash scripts/install.sh --config-dir \"$LT_CFG\" (o instalador repara escopos orfaos)."
  fi

  HAVE="$(basename "$INSTALL_PATH")"
  if [ "$HAVE" != "$WANT" ]; then
    # Comparacao SEMANTICA: ordem lexica escolheria 0.9.4 sobre 0.10.0.
    if [ -r "$REPO_ROOT/plugins/lt/lib/version-compare.sh" ]; then
      . "$REPO_ROOT/plugins/lt/lib/version-compare.sh"
      if vc_gt "$WANT" "$HAVE"; then
        emit "O harness LT instalado esta na $HAVE e o manifesto ja esta na $WANT. Ofereca rodar: bash scripts/update.sh --config-dir \"$LT_CFG\""
      fi
    fi
  fi

  if [ "$ENABLED" != "yes" ]; then
    emit "O harness LT esta em cache mas nao esta habilitado em $SET. Ofereca rodar: bash scripts/install.sh --config-dir \"$LT_CFG\""
  fi
done

# shadowed — symlink legado convivendo com o plugin
SHADOW=0
for e in "$LT_CFG/skills"/*; do
  [ -L "$e" ] || continue
  t="$(python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$e" 2>/dev/null)"
  case "$t" in */tools/modelo-generico/*) SHADOW=$((SHADOW+1)) ;; esac
done
if [ "$SHADOW" -gt 0 ]; then
  emit "Ha $SHADOW symlink(s) da distribuicao antiga convivendo com o plugin LT neste perfil. Isso cria DUAS fontes da mesma skill: a pessoa edita o repo e executa o cache, sem erro nenhum. Ofereca rodar: bash scripts/migrate-symlinks.sh --detect"
fi

# Tudo em dia: silencio.
exit 0
