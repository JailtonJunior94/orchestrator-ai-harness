#!/usr/bin/env bash
# validate-skill-prerequisites.sh
# Gate tool-neutro: dado um conjunto de arquivos tocados pela tarefa, bloqueia se
# a skill de linguagem correspondente nao estiver disponivel para descoberta
# (i.e., SKILL.md + references/INDEX.yaml ausentes na arvore de skills do plugin lt).
#
# Politica: nao bloqueia por "referencia X nao carregada" — referencias sao opt-in
# via when_to_load. Bloqueia somente por ausencia da camada de descoberta, garantindo
# que o agente sempre tenha o mapa.
#
# Mapeamento extensao → skill obrigatoria:
#   .go             → go-implementation
#   .ts, .tsx, .js, .mjs, .cjs, .jsx → node-implementation
#   .cs, .csproj    → dotnet-csharp-implementation
#
# Uso:
#   bash ${CLAUDE_PLUGIN_ROOT}/scripts/validate-skill-prerequisites.sh <files...>
#
# Variaveis:
#   AGENTS_ROOT             raiz onde skills/ resolve (default: CLAUDE_PLUGIN_ROOT, senao pwd). Sem camada de linguagem instalada, avisa e sai 0.
#   PREREQ_MODE=warn        nao bloqueia (exit 0) mesmo com skill ausente. Default: fail.
#
# Exit:
#   0 = OK ou warn-mode
#   1 = bloqueio (skill obrigatoria nao instalada)

set -euo pipefail

AGENTS_ROOT="${AGENTS_ROOT:-${CLAUDE_PLUGIN_ROOT:-$(pwd)}}"
MODE="${PREREQ_MODE:-fail}"

needed=""
for f in "$@"; do
  case "$f" in
    *.go) needed="$needed go-implementation" ;;
    *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs) needed="$needed node-implementation" ;;
    *.cs|*.csproj) needed="$needed dotnet-csharp-implementation" ;;
    *.py) needed="$needed python-implementation" ;;
  esac
done

# Deduplica
needed_uniq=$(printf '%s\n' $needed | awk '!seen[$0]++' | tr '\n' ' ')

# A camada de linguagem e' opcional nesta versao do plugin, e as skills do ciclo mandam seguir sem
# ela quando nao esta instalada. Sem esta checagem o gate exigia `node-implementation` para todo
# `.ts` e bloqueava toda tarefa TypeScript de todo repo consumidor. A camada conta como instalada
# quando ha' ao menos uma skill com `category: language` no frontmatter, o mesmo criterio de
# `lt-sdd.sh skills-available --category language`.
language_layer=0
for skill_md in "$AGENTS_ROOT"/skills/*/SKILL.md; do
  [[ -f "$skill_md" ]] || continue
  if awk '/^---[[:space:]]*$/ { n++; next } n == 1 && /^[[:space:]]*category:[[:space:]]*language[[:space:]]*$/ { found=1 } END { exit !found }' "$skill_md"; then
    language_layer=1
    break
  fi
done

if [[ -n "${needed// /}" && "$language_layer" -eq 0 ]]; then
  echo "AVISO: camada de linguagem nao instalada em $AGENTS_ROOT/skills; seguindo sem as skills de linguagem ($needed_uniq)." >&2
  exit 0
fi

missing=()
for skill in $needed_uniq; do
  [[ -z "$skill" ]] && continue
  skill_md="$AGENTS_ROOT/skills/$skill/SKILL.md"
  index="$AGENTS_ROOT/skills/$skill/references/INDEX.yaml"
  if [[ ! -f "$skill_md" || ! -f "$index" ]]; then
    missing+=("$skill")
  fi
done

if [[ ${#missing[@]} -eq 0 ]]; then
  exit 0
fi

{
  echo "BLOQUEIO: tarefa toca arquivos cuja skill obrigatoria nao esta acessivel."
  echo "Skills ausentes:"
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
