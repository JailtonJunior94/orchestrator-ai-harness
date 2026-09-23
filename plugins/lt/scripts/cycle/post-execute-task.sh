#!/usr/bin/env bash
# post-execute-task.sh
# Validacao programatica pos-execute-task.
# Fecha as fragilidades F2 (evidence physical), F13 (path absoluto),
# F24 (escalation de remark critico), F25 (checkpoint), F35 (git revert).
#
# Uso (modo CLI direto, invocavel pelo orquestrador via Bash tool):
#   bash ${CLAUDE_PLUGIN_ROOT}/scripts/cycle/post-execute-task.sh <prd-slug> <task-id> <yaml-file>
#
# Uso (modo stdin para pipelines):
#   echo "$YAML" | bash ${CLAUDE_PLUGIN_ROOT}/scripts/cycle/post-execute-task.sh <prd-slug> <task-id>
#
# Exit codes:
#   0 — todas validacoes passaram (warnings nao bloqueiam)
#   1 — pelo menos uma validacao falhou; mensagens em stderr
#   2 — argumentos invalidos
#
# Ativacao de validacoes mais caras (RF-04, default-on):
#   AI_VALIDATE_GIT_HISTORY default 1 — habilita F35 (patch declarado existe, bate com sha= e segue aplicado).
#   Opt-out explicito via AI_VALIDATE_GIT_HISTORY=0 (zero regressao quando desligado).

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Uso: $0 <prd-slug> <task-id> [yaml-file]" >&2
  exit 2
fi

PRD_SLUG="$1"
TASK_ID="$2"

contains_forbidden_path_syntax() {
  local value="$1"
  value="$(printf '%s' "$value" | tr '\\' '/')"
  [[ "$value" == /* || "$value" =~ ^[A-Za-z]:/ ]] ||
    [[ "$value" == ".." || "$value" == ../* || "$value" == */../* || "$value" == */.. ]]
}

if [[ -z "$PRD_SLUG" || "$PRD_SLUG" =~ [\\/] || "$PRD_SLUG" == *".."* ]]; then
  echo "FAIL F13: prd-slug inválido (absoluto ou traversal): $PRD_SLUG" >&2
  exit 2
fi
if ! [[ "$TASK_ID" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
  echo "FAIL F13: task-id inválido: $TASK_ID" >&2
  exit 2
fi

# Modo arquivo ou stdin
if [[ $# -ge 3 ]]; then
  YAML_FILE="$3"
else
  YAML_FILE=$(mktemp /tmp/post-execute-task.yaml.XXXXXX)
  trap 'rm -f "$YAML_FILE"' EXIT
  cat > "$YAML_FILE"
fi

if [[ ! -s "$YAML_FILE" ]]; then
  echo "FAIL: YAML vazio ou inexistente: $YAML_FILE" >&2
  exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
REPO_ROOT="$(cd -P "$REPO_ROOT" && pwd)"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib/specs-root.sh"
SPECS_ROOT="$(lt_specs_root "$REPO_ROOT")" || exit 1
PRD_PREFIX="${AI_PRD_PREFIX:-prd-}"
PRD_DIR="$SPECS_ROOT/$PRD_PREFIX$PRD_SLUG"

# DELEGACAO AO CLI EXTERNO — OPT-IN, NAO DEFAULT.
#
# Este bloco era o caminho padrao: exigia um binario para interpretar um contrato JSON e, sem
# ele, saia 1. O binario e' do harness de origem; ESTE plugin nao distribui binario nenhum — o
# motor SDD e' `lib/sdd.py`, e o artefato que `execute-task` produz e' o relatorio Markdown que
# `lt-sdd.sh seal-evidence` valida. Resultado na pratica: o default falhava em toda maquina
# ("binario harness lt ausente"), e o unico caminho que funcionava estava escondido atras de
# AI_SDD_LEGACY_HOOK_CONTRACT=1 — uma flag chamada "legado" para o unico modo suportado.
#
# Agora a delegacao so acontece quando alguem APONTA um binario de propria vontade, via
# AI_SPEC_BIN. Sem essa variavel, o hook segue para a validacao nativa abaixo.
if [[ -n "${AI_SPEC_BIN:-}" ]]; then
  if [[ ! -f "$YAML_FILE" ]]; then
    echo "FAIL: AI_SPEC_BIN definido, mas o resultado SDD ausente: $YAML_FILE" >&2
    exit 1
  fi
  if [[ "$AI_SPEC_BIN" == */* ]]; then
    if [[ ! -x "$AI_SPEC_BIN" ]]; then
      echo "FAIL: executavel AI_SPEC_BIN indisponivel: $AI_SPEC_BIN" >&2
      exit 1
    fi
  elif ! command -v "$AI_SPEC_BIN" >/dev/null 2>&1; then
    echo "FAIL: AI_SPEC_BIN='$AI_SPEC_BIN' nao esta no PATH" >&2
    exit 1
  fi
  "$AI_SPEC_BIN" validate-result execution "$YAML_FILE" --task-id "$TASK_ID"
  exit $?
fi

errors=0
warnings=0

trim() {
  echo "$1" | xargs
}

normalize_status() {
  local raw
  raw=$(trim "$1")
  printf "%s" "$raw" | tr '[:upper:]' '[:lower:]'
}

task_status() {
  local tasks_md="$1"
  local wanted_id="$2"
  local line tid status
  while IFS= read -r line; do
    case "$line" in
      "|"*) ;;
      *) continue ;;
    esac
    IFS='|' read -ra cells <<< "$line"
    [[ ${#cells[@]} -lt 4 ]] && continue
    tid=$(trim "${cells[1]}")
    [[ "$tid" == "$wanted_id" ]] || continue
    status=$(normalize_status "${cells[3]}")
    echo "$status"
    return 0
  done < "$tasks_md"
  return 1
}

# === Parse YAML estritamente ===
status=""
report_path=""
summary=""
status_count=0
report_count=0
summary_count=0
line_count=0

while IFS= read -r line || [[ -n "$line" ]]; do
  stripped=$(trim "$line")
  [[ -z "$stripped" ]] && continue
  line_count=$((line_count+1))
  case "$stripped" in
    status:*)
      status_count=$((status_count+1))
      status=$(trim "${stripped#status:}")
      ;;
    report_path:*)
      report_count=$((report_count+1))
      report_path=$(trim "${stripped#report_path:}")
      report_path=${report_path#\"}
      report_path=${report_path%\"}
      report_path=${report_path#\'}
      report_path=${report_path%\'}
      ;;
    summary:*)
      summary_count=$((summary_count+1))
      summary=$(trim "${stripped#summary:}")
      ;;
    *)
      echo "FAIL: contract violation — linha YAML inesperada: $stripped" >&2
      errors=$((errors+1))
      ;;
  esac
done < "$YAML_FILE"

if [[ "$line_count" -ne 3 ]]; then
  echo "FAIL: contract violation — YAML deve conter exatamente status, report_path e summary (linhas=$line_count)" >&2
  errors=$((errors+1))
fi
if [[ "$status_count" -ne 1 || "$report_count" -ne 1 || "$summary_count" -ne 1 ]]; then
  echo "FAIL: contract violation — campos obrigatorios devem aparecer uma unica vez (status=$status_count report_path=$report_count summary=$summary_count)" >&2
  errors=$((errors+1))
fi
if [[ -z "$summary" ]]; then
  echo "FAIL: contract violation — summary ausente ou vazio" >&2
  errors=$((errors+1))
fi

# Validar status canonico
if ! [[ "$status" =~ ^(done|blocked|failed|needs_input)$ ]]; then
  echo "FAIL: status invalido ou ausente: '$status'" >&2
  errors=$((errors+1))
fi

# === F2 + F13: evidence physical + containment de path ===
if [[ -z "$report_path" ]]; then
  echo "FAIL F2: report_path ausente no YAML" >&2
  errors=$((errors+1))
elif contains_forbidden_path_syntax "$report_path"; then
  echo "FAIL F13: report_path com path absoluto ou traversal rejeitado: $report_path" >&2
  errors=$((errors+1))
else
  resolved="$REPO_ROOT/$report_path"
  # realpath resolve o componente final e todos os symlinks. Comparar o caminho
  # físico impede que um link aparentemente relativo saia do repositório.
  if [[ -e "$resolved" || -L "$resolved" ]]; then
    physical_resolved="$(realpath "$resolved" 2>/dev/null || true)"
    if [[ -z "$physical_resolved" ]]; then
      echo "FAIL F13: report_path não pode ser resolvido com realpath: $report_path" >&2
      errors=$((errors+1))
    elif [[ "$physical_resolved" != "$REPO_ROOT" && "$physical_resolved" != "$REPO_ROOT/"* ]]; then
      echo "FAIL F13: report_path resolve fora do repositório: $report_path -> $physical_resolved" >&2
      errors=$((errors+1))
    else
      resolved="$physical_resolved"
    fi
  fi
  if [[ "$status" == "done" && ! -s "$resolved" ]]; then
    echo "FAIL F2: missing evidence — $resolved ausente ou vazio" >&2
    errors=$((errors+1))
  fi
fi

# === F24: escalation de remark critico se status=done ===
if [[ "$status" == "done" && -n "$report_path" && -s "$REPO_ROOT/$report_path" ]]; then
  if grep -iE "\[(critical|security|blocker|high)\]" "$REPO_ROOT/$report_path" >/dev/null 2>&1; then
    echo "FAIL F24: report contem remark critico em tarefa marcada done — escalar para BLOCKED:" >&2
    grep -inE "\[(critical|security|blocker|high)\]" "$REPO_ROOT/$report_path" | head -3 | sed 's/^/  /' >&2
    errors=$((errors+1))
  fi
fi

# === F25: checkpoint deve existir se status=done ===
# Default: FAIL bloqueante. Override via AI_ALLOW_MISSING_CHECKPOINT=1 (back compat com execute-task <v1.4)
if [[ "$status" == "done" ]]; then
  checkpoint="$PRD_DIR/.checkpoints/${TASK_ID}.json"
  if [[ ! -s "$checkpoint" ]]; then
    if [[ "${AI_ALLOW_MISSING_CHECKPOINT:-0}" == "1" ]]; then
      echo "WARN F25: checkpoint ausente em $checkpoint (back compat: AI_ALLOW_MISSING_CHECKPOINT=1)" >&2
      warnings=$((warnings+1))
    else
      echo "FAIL F25: checkpoint ausente em $checkpoint — execute-task Stage 5.3 nao escreveu JSON antes de mutar tasks.md. Re-execute a tarefa ou exporte AI_ALLOW_MISSING_CHECKPOINT=1 (nao recomendado)." >&2
      errors=$((errors+1))
    fi
  fi
fi

# === F35: o patch declarado existe, tem o hash do relatorio e continua aplicado ===
#
# `sha=` e' o SHA-256 do patch da tarefa, o mesmo `patch_sha256` do execution-result.json que
# validate-task-evidence exige. O F35 antigo tratava esse valor como objeto do git e rodava
# `git cat-file -e`: um hash de patch nunca e' objeto de um repo SHA-1, entao nenhuma tarefa
# fechava `done` com a configuracao padrao. O harness nao commita (R-GOV-001), logo a prova nao
# pode depender de commit: ela e' o arquivo de patch, o hash dele e o fato de as mudancas ainda
# estarem na arvore. `git apply --reverse --check` so' passa se o patch continua aplicado, o que
# detecta o revert que o F35 original queria pegar.
if [[ "${AI_VALIDATE_GIT_HISTORY:-1}" == "1" && "$status" == "done" && -n "$report_path" && -s "$REPO_ROOT/$report_path" ]]; then
  diff_sha=$(grep -E "^sha=" "$REPO_ROOT/$report_path" 2>/dev/null | head -1 | sed 's/^sha=//' | xargs || true)
  result_ref=$(grep -E "^result_path[[:space:]]*=" "$REPO_ROOT/$report_path" 2>/dev/null | head -1 | sed -E 's/^result_path[[:space:]]*=[[:space:]]*//' | xargs || true)
  if ! [[ "$diff_sha" =~ ^[0-9a-fA-F]{64}$ ]]; then
    echo "FAIL F35: sha= deve ser o patch_sha256 da tarefa (64 hex); recebido '${diff_sha:-vazio}'" >&2
    errors=$((errors+1))
  elif [[ -z "$result_ref" || ! -f "$REPO_ROOT/${result_ref%%#*}" ]]; then
    echo "FAIL F35: result_path ausente ou inexistente no relatorio; sem ele o patch nao e' localizavel" >&2
    errors=$((errors+1))
  else
    patch_ref=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8")).get("patch_ref", ""))' "$REPO_ROOT/${result_ref%%#*}" 2>/dev/null || true)
    patch_file="$REPO_ROOT/${patch_ref%%#*}"
    if [[ -z "$patch_ref" ]] || contains_forbidden_path_syntax "$patch_ref" || [[ ! -f "$patch_file" ]]; then
      echo "FAIL F35: patch_ref '${patch_ref:-vazio}' ausente, fora do repositorio ou inexistente" >&2
      errors=$((errors+1))
    else
      actual_sha=$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$patch_file")
      if [[ "$(printf '%s' "$actual_sha" | tr '[:upper:]' '[:lower:]')" != "$(printf '%s' "$diff_sha" | tr '[:upper:]' '[:lower:]')" ]]; then
        echo "FAIL F35: o patch $patch_ref mudou depois do relatorio (sha= $diff_sha, arquivo $actual_sha)" >&2
        errors=$((errors+1))
      elif [[ -s "$patch_file" ]] && ! git -C "$REPO_ROOT" apply --reverse --check "$patch_file" >/dev/null 2>&1; then
        echo "FAIL F35: o patch $patch_ref nao esta mais aplicado na arvore (revert ou mudanca por cima)" >&2
        errors=$((errors+1))
      fi
    fi
  fi
fi

# === Consistencia tasks.md para done ===
if [[ "$status" == "done" ]]; then
  tasks_md="$PRD_DIR/tasks.md"
  if [[ ! -f "$tasks_md" ]]; then
    echo "FAIL: tasks.md ausente para validar status: $tasks_md" >&2
    errors=$((errors+1))
  else
    current_status=$(task_status "$tasks_md" "$TASK_ID" || true)
    if [[ -z "$current_status" ]]; then
      echo "FAIL: status drift — tarefa $TASK_ID nao encontrada em tasks.md" >&2
      errors=$((errors+1))
    elif [[ "$current_status" != "done" ]]; then
      echo "FAIL: status drift — tarefa $TASK_ID retornou done mas tasks.md esta $current_status" >&2
      errors=$((errors+1))
    fi
  fi
fi

# === RF-53: prova de aprovacao obrigatoria para status=done ===
# O contrato legado NAO e caminho legitimo para fechar tarefa sem prova. Antes
# desta correcao AI_SDD_LEGACY_HOOK_CONTRACT=1 desviava de
# `harness lt validate-result execution` e o ramo legado jamais mencionava veredito,
# APPROVED ou criterios de aceite: um relatorio sem conteudo nenhum saia com 0.
# A variavel continua desviando apenas a FORMA do contrato (YAML vs JSON v2);
# o DESFECHO passa pelo validador canonico de evidencia nos dois caminhos.
if [[ "$status" == "done" ]]; then
  evidence_validator=""
  for candidate_dir in "${CLAUDE_PLUGIN_ROOT:-$REPO_ROOT}/scripts"; do
    if [[ -r "$candidate_dir/validate-task-evidence.sh" ]]; then
      evidence_validator="$candidate_dir/validate-task-evidence.sh"
      break
    fi
  done
  if [[ -z "$evidence_validator" ]]; then
    echo "FAIL RF-53: validate-task-evidence.sh ausente em ${CLAUDE_PLUGIN_ROOT}/scripts" >&2
    errors=$((errors+1))
  elif [[ -z "$report_path" || ! -s "$REPO_ROOT/$report_path" ]]; then
    echo "FAIL RF-53: tarefa done sem relatorio de execucao utilizavel para comprovar aprovacao" >&2
    errors=$((errors+1))
  elif ! bash "$evidence_validator" "$REPO_ROOT/$report_path" >&2; then
    echo "FAIL RF-53: relatorio de execucao nao comprova aprovacao — AI_SDD_LEGACY_HOOK_CONTRACT nao reabre este gate" >&2
    errors=$((errors+1))
  fi
fi

# === Resumo ===
if [[ "$errors" -gt 0 ]]; then
  echo "post-execute-task: $errors erro(s), $warnings warning(s) para $PRD_SLUG/$TASK_ID" >&2
  exit 1
fi

if [[ "$warnings" -gt 0 ]]; then
  echo "post-execute-task: OK com $warnings warning(s) para $PRD_SLUG/$TASK_ID" >&2
else
  echo "post-execute-task: OK ($PRD_SLUG/$TASK_ID, status=$status)" >&2
fi
exit 0
