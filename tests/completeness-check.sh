#!/usr/bin/env bash
# tests / completeness-check.sh — banner de sucesso: TUDO ENTREGUE
#
# Inventario por nome CRUZADO COM DISCO.
#
# POR QUE O CRUZAMENTO E' O PONTO: um inventario que so confere o que ele mesmo lista e' verde
# por construcao. O harness de referencia reportou "11 de 13 hooks" em verde por meses porque a
# lista canonica nao era comparada com `ls`. Aqui cada bloco termina comparando com o disco.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
cd "$REPO"

if [ -t 1 ]; then C_OK=$'\033[32m'; C_BAD=$'\033[31m'; C_OFF=$'\033[0m'
else C_OK=""; C_BAD=""; C_OFF=""; fi
OK=0; BAD=0
ok()  { OK=$((OK+1));  printf '  %s✓%s %s\n' "$C_OK" "$C_OFF" "$1"; }
bad() { BAD=$((BAD+1)); printf '  %s✗%s %s\n' "$C_BAD" "$C_OFF" "$1" >&2; }
sec() { printf '\n▸ %s\n' "$1"; }

# inventario <rotulo> <comando-que-conta-o-disco> <lista-canonica...>
check_set() {
  label="$1"; disk_glob="$2"; shift 2
  declared=0; missing=""
  for item in "$@"; do
    declared=$((declared+1))
    [ -e "$item" ] || missing="$missing $(basename "$item")"
  done
  disk="$(eval "$disk_glob" 2>/dev/null | wc -l | tr -d ' ')"
  if [ -n "$missing" ]; then
    bad "$label: declarado mas ausente em disco:$missing"
  elif [ "$declared" != "$disk" ]; then
    # O caso que o harness de referencia deixou passar por meses.
    bad "$label: a lista canonica tem $declared, o disco tem $disk — ha componente NAO inventariado"
    eval "$disk_glob" | sed 's/^/      /' >&2
  else
    ok "$label: $declared declarados == $disk em disco"
  fi
}

sec "hooks"
check_set "hooks" "ls -1 plugins/lt/hooks/*.sh" \
  plugins/lt/hooks/session-start.sh \
  plugins/lt/hooks/pre-bash-block-destructive.sh \
  plugins/lt/hooks/pre-bash-block-sensitive-paths.sh \
  plugins/lt/hooks/pre-write-block-sensitive-paths.sh \
  plugins/lt/hooks/pre-write-scan-secrets.sh \
  plugins/lt/hooks/pre-write-spec-coverage-warn.sh \
  plugins/lt/hooks/post-tool-capture-tokens.sh \
  plugins/lt/hooks/post-skill-fire.sh \
  plugins/lt/hooks/user-prompt-block-sensitive-paths.sh \
  plugins/lt/hooks/user-prompt-detect-secrets.sh \
  plugins/lt/hooks/user-prompt-context-warning.sh \
  plugins/lt/hooks/pre-bash-git-operation-gate.sh \
  plugins/lt/hooks/pre-write-validate-preload.sh \
  plugins/lt/hooks/post-tool-validate-governance.sh \
  plugins/lt/hooks/subagent-stop-wrapper.sh \
  plugins/lt/hooks/stop-validate-session-end.sh

sec "commands"
check_set "commands" "ls -1 plugins/lt/commands/*.md" \
  plugins/lt/commands/lt-doctor.md \
  plugins/lt/commands/lt-approve.md \
  plugins/lt/commands/lt-migrate-legacy.md \
  plugins/lt/commands/0-setup.md

sec "skills do ciclo SDD"
check_set "skills SDD" "ls -1d plugins/lt/skills/{agent-governance,analyze-project,bugfix,create-prd,create-tasks,create-technical-specification,execute-all-tasks,execute-task,refactor,review,us-to-prd}" \
  plugins/lt/skills/agent-governance plugins/lt/skills/analyze-project plugins/lt/skills/bugfix \
  plugins/lt/skills/create-prd plugins/lt/skills/create-tasks \
  plugins/lt/skills/create-technical-specification plugins/lt/skills/execute-all-tasks \
  plugins/lt/skills/execute-task plugins/lt/skills/refactor plugins/lt/skills/review \
  plugins/lt/skills/us-to-prd

sec "libs e scripts do plugin"
for f in plugins/lt/lib/lt-lock.sh plugins/lt/lib/hook-common.sh plugins/lt/lib/version-compare.sh \
         plugins/lt/lib/sdd.py plugins/lt/lib/secret_scan.py plugins/lt/lib/sensitive_paths.py \
         plugins/lt/lib/destructive_guard.py plugins/lt/lib/context_pct.py \
         plugins/lt/lib/prompt_secret_scan.py plugins/lt/lib/telemetry_line.py \
         plugins/lt/lib/host-dispatch.py plugins/lt/scripts/reconcile-hosts.py \
         plugins/lt/scripts/approve.sh plugins/lt/scripts/doctor.sh \
         plugins/lt/scripts/guided-mode.sh plugins/lt/scripts/lt-sdd.sh \
         plugins/lt/config/constitution.md plugins/lt/config/policy-texts.md \
         plugins/lt/config/secret-patterns.json plugins/lt/config/sensitive-paths.json \
         plugins/lt/config/preferences.defaults.json; do
  [ -e "$f" ] && ok "$(basename "$f")" || bad "ausente: $f"
done

sec "ferramental do repo"
for f in scripts/install.sh scripts/update.sh scripts/uninstall.sh scripts/install-detect.sh \
         scripts/migrate-symlinks.sh scripts/lib/reconcile-plugins.py \
         scripts/lib/provision-statusline.py tests/smoke/run.sh tests/e2e/run.sh \
         tests/unit/run.sh tests/unit/lib/assert.sh docs/policy/ia-automacao.md \
         docs/host-facts.md docs/benchmarks/skill-listing.json docs/benchmarks/plugin-token-cost.json \
         scripts/validate-plugins.sh scripts/validate-frontmatter.sh scripts/measure-skill-budget.sh \
         scripts/plugin-token-cost.sh scripts/check-cost-baseline.sh scripts/validate-playbook-counts.sh \
         scripts/lib/check-plugin-counts.py scripts/lib/unreconcile-plugins.py \
         plugins/lt/lib/preferences.sh enterprise/uninstall.sh enterprise/uninstall.ps1 \
         tests/command-glossary-check.sh tests/language-policy-check.sh tests/unit/README.md; do
  [ -e "$f" ] && ok "$(basename "$f")" || bad "ausente: $f"
done

sec "governanca e documentacao"
for f in .github/CODEOWNERS .github/PULL_REQUEST_TEMPLATE.md .github/ISSUE_TEMPLATE/bug.md \
         .github/ISSUE_TEMPLATE/feature.md .github/ISSUE_TEMPLATE/config.yml SECURITY.md \
         CONTRIBUTING.md PILOT-SETUP.md docs/INDEX.md docs/VERSIONING.md docs/RELEASE-CHECKLIST.md \
         docs/PLUGIN-DEVELOPMENT.md docs/command-glossary.md docs/language-policy.md \
         docs/enterprise-rollout.md enterprise/README.md plugins/lt/README.md; do
  [ -e "$f" ] && ok "$(basename "$f")" || bad "ausente: $f"
done

sec "componentes adiados (config/deferred-components.txt)"
# O arquivo declara o que foi DELIBERADAMENTE deixado de fora. Duas formas de ele mentir, e as
# duas sao cobradas aqui (no-phantom-refs.test.sh cobre skills e commands; este bloco cobre o
# resto do disco):
#   1. o nome adiado PASSOU a existir — como plugin, hook, skill ou command — e a entrada nao saiu;
#   2. a data de revisao venceu: adiamento sem prazo vira desculpa permanente.
TODAY="$(date -u +%Y-%m-%d)"
DEF_N=0; DEF_BAD=0
while IFS='|' read -r n _motivo _cond until; do
  n="$(printf '%s' "$n" | tr -d ' ')"
  case "$n" in ''|\#*) continue ;; esac
  DEF_N=$((DEF_N+1))
  until="$(printf '%s' "$until" | tr -d ' ')"
  if [ -d "plugins/$n" ] || [ -f "plugins/lt/hooks/$n.sh" ] || [ -f "plugins/lt/skills/$n/SKILL.md" ] \
     || [ -f "plugins/lt/commands/$n.md" ]; then
    bad "adiado mas JA EXISTE em disco (remova de config/deferred-components.txt): $n"; DEF_BAD=1
  fi
  if ! printf '%s' "$until" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
    bad "adiado sem data de revisao valida: $n ($until)"; DEF_BAD=1
  elif [ "$until" \< "$TODAY" ]; then
    bad "adiamento vencido em $until: $n — revise, entregue ou renove com motivo"; DEF_BAD=1
  fi
done < config/deferred-components.txt
[ "$DEF_BAD" -eq 0 ] && ok "$DEF_N adiados: nenhum existe em disco, nenhum vencido"

printf '\n───────────────────────────────\n'
printf '%d ok · %d falha\n' "$OK" "$BAD"
if [ "$BAD" -eq 0 ]; then printf 'TUDO ENTREGUE\n'; exit 0; fi
printf 'INVENTARIO INCOMPLETO\n' >&2; exit 1
