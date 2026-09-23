#!/usr/bin/env bash
# lt / lib / preferences.sh
#
# Resolve uma preferencia do harness por chave, com precedencia por CHAVE (nao por arquivo):
#
#   1. <projeto>/.lt/preferences.json          versionado pelo squad, via PR
#   2. <perfil>/lt/preferences.json            maquina de quem usa (CLAUDE_CONFIG_DIR ou ~/.claude)
#   3. config/preferences.defaults.json        default do plugin — sempre presente
#
# O VALOR E' ENUM, NUNCA TEXTO LIVRE. Todo valor lido e' conferido contra `_enums` do arquivo de
# defaults; fora da enum, a camada e' ignorada, o proximo nivel vale, e o nome do defeito
# (lt_pref_unknown_enum) sai no stderr. Quem consome o valor o usa como CHAVE para um texto
# canonico de config/policy-texts.md — sem essa indirecao, um .lt/preferences.json de repo de
# terceiro seria vetor de injecao no system prompt. Por isso esta lib tambem recusa valor com
# caractere fora de [A-Za-z0-9_.-] ANTES de comparar: nada do arquivo atravessa sem ser enum.
#
# jq QUANDO EXISTE, python3 QUANDO NAO. Hook roda em toda chamada de ferramenta; jq e' o mais
# barato. Na frota ha maquina sem jq, e cair para "sem preferencia" ali mudaria o comportamento
# do harness por um detalhe de instalacao. Sem nenhum dos dois, o default do plugin vale e o
# motivo sai no stderr (lt_pref_no_parser) — nunca silencio.
#
# USO COMO LIB (hooks):   . "$PLUGIN_ROOT/lib/preferences.sh"; v="$(lt_pref_get code_comments)"
# USO COMO CLI (doctor):  bash lib/preferences.sh get <chave> [projeto]
#                         bash lib/preferences.sh source <chave> [projeto]   # qual camada venceu
#
# bash 3.2: sem arrays associativos, sem ${var,,}. Sem `set -e` quando carregado por `.`: a
# lib nao pode mudar o modo de erro de quem a carrega.

LT_PREF_PLUGIN_ROOT="${LT_PREF_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}}"

# lt_pref__raw <arquivo> <chave> — imprime o valor string da chave no nivel raiz, ou nada.
lt_pref__raw() {
  [ -r "$1" ] || return 1
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg k "$2" 'if type == "object" then (.[$k] // empty | strings) else empty end' "$1" 2>/dev/null
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$1" "$2" <<'PY' 2>/dev/null
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    sys.exit(0)
v = d.get(sys.argv[2]) if isinstance(d, dict) else None
if isinstance(v, str):
    print(v)
PY
    return 0
  fi
  printf '[lt] lt_pref_no_parser: sem jq nem python3; usando o default do plugin para %s\n' "$2" >&2
  return 1
}

# lt_pref__enum <chave> — valores validos, um por linha, lidos de _enums do arquivo de defaults.
lt_pref__enum() {
  lt_pref__defaults="$LT_PREF_PLUGIN_ROOT/config/preferences.defaults.json"
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg k "$1" '._enums[$k] // [] | .[] | strings' "$lt_pref__defaults" 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
[print(v) for v in d.get("_enums",{}).get(sys.argv[2],[]) if isinstance(v,str)]' "$lt_pref__defaults" "$1" 2>/dev/null
  fi
}

lt_pref__valid() {  # <chave> <valor>
  case "$2" in ''|*[!A-Za-z0-9_.-]*) return 1 ;; esac
  lt_pref__enum "$1" | grep -qxF -e "$2"
}

# lt_pref_resolve <chave> [projeto] — imprime "<camada>\t<valor>".
lt_pref_resolve() {
  lt_pref_key="$1"
  lt_pref_project="${2:-${CLAUDE_PROJECT_DIR:-.}}"
  case "$lt_pref_key" in ''|_*|*[!a-z0-9_]*)
    printf '[lt] lt_pref_bad_key: chave invalida: %s\n' "$lt_pref_key" >&2; return 2 ;;
  esac
  lt_pref_cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  for lt_pref_layer in project machine default; do
    case "$lt_pref_layer" in
      project) lt_pref_file="$lt_pref_project/.lt/preferences.json" ;;
      machine) lt_pref_file="$lt_pref_cfg/lt/preferences.json" ;;
      default) lt_pref_file="$LT_PREF_PLUGIN_ROOT/config/preferences.defaults.json" ;;
    esac
    [ -r "$lt_pref_file" ] || continue
    lt_pref_val="$(lt_pref__raw "$lt_pref_file" "$lt_pref_key" | head -1)"
    [ -n "$lt_pref_val" ] || continue
    if lt_pref__valid "$lt_pref_key" "$lt_pref_val"; then
      printf '%s\t%s\n' "$lt_pref_layer" "$lt_pref_val"
      return 0
    fi
    # O valor nao e' ecoado: so a camada e a chave. Ecoar o conteudo reabriria, no stderr que o
    # host mostra ao agente, o mesmo vetor que a enum fecha.
    printf '[lt] lt_pref_unknown_enum: %s em %s fora da enum; camada ignorada\n' "$lt_pref_key" "$lt_pref_layer" >&2
  done
  return 1
}

# lt_pref_get <chave> [projeto] — imprime so o valor. Exit 1 se nenhuma camada tem valor valido.
lt_pref_get() {
  lt_pref_line="$(lt_pref_resolve "$@")" || return $?
  printf '%s\n' "${lt_pref_line#*	}"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  set -euo pipefail
  case "${1:-}" in
    get) shift; lt_pref_get "$@" ;;
    source) shift; lt_pref_resolve "$@" | cut -f1 ;;
    *) printf 'uso: preferences.sh get|source <chave> [projeto]\n' >&2; exit 2 ;;
  esac
fi
