#!/usr/bin/env bash
# tests / unit / scripts / cross-repo-and-args.test.sh
#
# Tres defeitos encontrados rodando `create-tasks` de verdade:
#
# 1. `--category processual` devolvia VAZIO. A regra escrita em `create-tasks` Etapa 4.1 e' que
#    skill sem `category` no frontmatter conta como processual, mas o filtro comparava com a
#    string crua. O agente que seguisse a instrucao da skill concluiria que nao existe skill
#    processual nenhuma — justamente quando as candidatas reais sao as que importam.
#
# 2. Dependencia cross-PRD resolvia sempre no repo atual. Uma feature que atravessa repositorios
#    — o consumidor depende do produtor — nao tinha como ser expressa sem romper I-5.
#
# 3. `sync-spec-hash` e `check-spec-drift` so aceitavam diretorio, enquanto TODA a prosa das
#    skills passa `.../tasks.md`. Seguir a instrucao escrita produzia "prd.md nao encontrado em
#    .../tasks.md": mensagem que culpa o artefato quando o errado foi o formato do argumento.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
. "$REPO/tests/unit/lib/assert.sh"

SDD="$REPO/plugins/lt/lib/sdd.py"
PLUGIN="$REPO/plugins/lt"
W="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$W"' EXIT

clean() { env -u CLAUDE_PROJECT_DIR -u LT_PROJECT_DIR -u LT_TASKS_ROOT -u AI_TASKS_ROOT "$@"; }

describe "categoria de skill: ausente conta como processual"

# O plugin distribuido so' carrega skills de governanca do ciclo SDD; skill processual vem do
# squad. A regra "sem category conta como processual" se prova numa arvore de plugin montada
# aqui: as skills reais mais uma skill sem `category`, como a que um squad adicionaria.
FIX="$W/plugin-fixture"
mkdir -p "$FIX/skills/squad-sem-categoria"
for d in "$PLUGIN"/skills/*/; do ln -s "$d" "$FIX/skills/$(basename "$d")"; done
printf -- '---\nname: squad-sem-categoria\ndescription: fixture\n---\n# x\n' > "$FIX/skills/squad-sem-categoria/SKILL.md"

PROC="$(CLAUDE_PLUGIN_ROOT="$FIX" clean python3 "$SDD" skills-available --category processual | cut -f1)"
[ -n "$PROC" ] && ok "--category processual devolve skills" || bad "--category processual voltou vazio"

GOV="$(CLAUDE_PLUGIN_ROOT="$PLUGIN" clean python3 "$SDD" skills-available --category governance | cut -f1)"
assert_contains "$GOV" "execute-task" "governance continua listando as skills do ciclo"
assert_not_contains "$PROC" "execute-task" "skill de governanca nao vaza para processual"

# `-` como categoria era o sintoma: significava "sem opiniao" numa saida que o agente le como dado.
RAW="$(CLAUDE_PLUGIN_ROOT="$FIX" clean python3 "$SDD" skills-available | cut -f2 | sort -u)"
assert_not_contains "$RAW" "-" "nenhuma skill sai com categoria '-'"

describe "cross-PRD atravessa repositorio quando declarado"

mkdir -p "$W/consumer/.lt" "$W/producer/.specs/prd-pipeline"
( cd "$W/consumer" && git init -q ); ( cd "$W/producer" && git init -q )
printf 'tasks_root: .specs\nspec_repos:\n  pipeline: ../producer\n' > "$W/consumer/.lt/config.yaml"

GOT="$( cd "$W/consumer" && clean python3 "$SDD" specs-root --slug pipeline )"
assert_eq "$GOT" "$W/producer/.specs/prd-pipeline" "slug mapeado resolve no repo vizinho"

GOT="$( cd "$W/consumer" && clean python3 "$SDD" specs-root --slug outra )"
assert_eq "$GOT" "$W/consumer/.specs/prd-outra" "slug nao mapeado continua local"

# I-5: criar spec dentro de outro repo a partir daqui e' exatamente o erro que o invariante
# existe para impedir. O bundle do outro repo nasce la.
create_mapped() { ( cd "$W/consumer" && clean python3 "$SDD" specs-root --slug pipeline --create ); }
assert_exit_code 3 create_mapped

# Mapeamento apontando para caminho inexistente falha alto, nao devolve caminho fantasma.
printf 'tasks_root: .specs\nspec_repos:\n  fantasma: ../nao-existe\n' > "$W/consumer/.lt/config.yaml"
ghost() { ( cd "$W/consumer" && clean python3 "$SDD" specs-root --slug fantasma ); }
assert_exit_code 3 ghost

describe "subcomandos de bundle aceitam diretorio E arquivo"

mkdir -p "$W/bundle/.lt/specs/prd-x"
( cd "$W/bundle" && git init -q )
B="$W/bundle/.lt/specs/prd-x"
printf '# PRD\n\n- RF-01: algo\n' > "$B/prd.md"
printf '# TechSpec\n' > "$B/techspec.md"
printf '# Tasks\n\n| # | T | Status | Dependências | Paralelizável | Skills |\n|---|---|---|---|---|---|\n| 1.0 | x | pending | — | — | — |\n\nRF-01\n' > "$B/tasks.md"

sync_dir()  { ( cd "$W/bundle" && clean python3 "$SDD" sync-spec-hash .lt/specs/prd-x ); }
sync_file() { ( cd "$W/bundle" && clean python3 "$SDD" sync-spec-hash .lt/specs/prd-x/tasks.md ); }
assert_exit_code 0 sync_dir
assert_exit_code 0 sync_file

drift_file() { ( cd "$W/bundle" && clean python3 "$SDD" check-spec-drift .lt/specs/prd-x/tasks.md ); }
assert_exit_code 0 drift_file

valid_file() { ( cd "$W/bundle" && clean python3 "$SDD" validate-sdd .lt/specs/prd-x/tasks.md ); }
assert_exit_code 0 valid_file

end_describe
