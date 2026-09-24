#!/usr/bin/env bash
# validate-skill-prerequisites.sh
# Gate tool-neutro: dado um conjunto de arquivos tocados pela tarefa, bloqueia se
# a skill de linguagem correspondente estiver instalada pela metade (SKILL.md presente
# e references/INDEX.yaml ausente na arvore de skills do plugin lt).
#
# Politica: nao bloqueia por "referencia X nao carregada", porque referencias sao opt-in
# via when_to_load. Bloqueia somente quando a skill existe e o mapa de descoberta dela
# falta, garantindo que o agente sempre tenha o mapa da skill que vai carregar.
#
# Mapeamento extensao para skill:
#   .go             : go-guideline
#   .ts, .tsx, .js, .mjs, .cjs, .jsx : node-implementation
#   .cs, .csproj    : dotnet-csharp-implementation
#   .py             : python-implementation
#
# Uso:
#   bash ${CLAUDE_PLUGIN_ROOT}/scripts/validate-skill-prerequisites.sh <files...>
#
# Variaveis:
#   AGENTS_ROOT             raiz onde skills/ resolve (default: CLAUDE_PLUGIN_ROOT, senao pwd). Linguagem sem skill instalada: avisa e sai 0.
#   PREREQ_MODE=warn        nao bloqueia (exit 0) mesmo com skill ausente. Default: fail.
#
# Exit:
#   0 = OK ou warn-mode
#   1 = bloqueio (skill da linguagem instalada sem references/INDEX.yaml)

set -euo pipefail

AGENTS_ROOT="${AGENTS_ROOT:-${CLAUDE_PLUGIN_ROOT:-$(pwd)}}"
MODE="${PREREQ_MODE:-fail}"

needed=""
for f in "$@"; do
  case "$f" in
    *.go) needed="$needed go-guideline" ;;
    *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs) needed="$needed node-implementation" ;;
    *.cs|*.csproj) needed="$needed dotnet-csharp-implementation" ;;
    *.py) needed="$needed python-implementation" ;;
  esac
done

# Deduplica
needed_uniq=$(printf '%s\n' $needed | awk '!seen[$0]++' | tr '\n' ' ')

# A camada de linguagem e' opcional POR LINGUAGEM. A primeira versao deste gate tratava a
# camada como um bloco unico: bastava existir uma skill com `category: language` para que
# todas as linguagens do mapa passassem a ser exigidas. Com so' a skill de Go publicada, isso
# bloqueava toda tarefa TypeScript, Python e C# de todo repo consumidor. Agora a ausencia da
# skill de uma linguagem so' gera aviso; o bloqueio fica para a skill instalada pela metade
# (SKILL.md sem INDEX.yaml), que e' instalacao quebrada, nao escolha de escopo.
missing=()
absent=""
for skill in $needed_uniq; do
  [[ -z "$skill" ]] && continue
  skill_md="$AGENTS_ROOT/skills/$skill/SKILL.md"
  index="$AGENTS_ROOT/skills/$skill/references/INDEX.yaml"
  if [[ ! -f "$skill_md" ]]; then
    absent="$absent $skill"
  elif [[ ! -f "$index" ]]; then
    missing+=("$skill")
  fi
done

if [[ -n "${absent// /}" ]]; then
  echo "AVISO: camada de linguagem sem skill instalada em $AGENTS_ROOT/skills para:$absent; seguindo sem ela." >&2
fi

if [[ ${#missing[@]} -eq 0 ]]; then
  exit 0
fi

{
  echo "BLOQUEIO: skill de linguagem instalada sem o mapa de referencias."
  echo "Skills incompletas:"
  for s in ${missing[@]+"${missing[@]}"}; do
    echo "  - $s ($AGENTS_ROOT/skills/$s/{SKILL.md,references/INDEX.yaml})"
  done
  echo
  echo "Acao: reinstale o plugin lt (marketplace) ou aponte AGENTS_ROOT para a raiz que contem skills/."
  echo "Override (nao recomendado): export PREREQ_MODE=warn"
} >&2

if [[ "$MODE" == "warn" ]]; then
  exit 0
fi
exit 1
