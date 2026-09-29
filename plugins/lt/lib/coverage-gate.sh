#!/usr/bin/env bash
# plugins/lt/lib/coverage-gate.sh — gate de cobertura R-TEST-002.1, compartilhado pelos validadores
# de evidência de tarefa, bugfix e refactor.
#
# Uso (sourced): `. lib/coverage-gate.sh` e depois `lt_coverage_check <relatorio.md>`. Imprime uma
# linha `FALTANDO: ...` por problema e devolve 1 se houver algum.
#
# Um dono só: antes o gate vivia dentro de validate-task-evidence.sh e bugfix e refactor não tinham
# gate nenhum, só prosa na skill. Três cópias divergiriam na primeira correção; por isso a lógica
# mora aqui e os validadores só chamam.
#
# O bloco `## Coverage` traz um grupo por pacote tocado:
#
#   package=<nome>
#   before=<n>% | n/a      (n/a = pacote novo, sem medida anterior)
#   after=<n>%  | n/a      (n/a só com diff sem código executável)
#   delta=<n>%  | n/a
#   log=<caminho relativo à raiz do repo>   (obrigatório quando after é número)
#
# Por que o piso vale para o pacote tocado e não para o diff nem para o projeto: medir só as linhas
# do diff exige ferramenta de diff coverage por linguagem, que a frota não tem, e medir o projeto
# inteiro trava para sempre um repositório legado. Pelo pacote, a tarefa que mexe num módulo mal
# testado paga a dívida daquele módulo, e nada além dele. Não há exceção de legado: é decisão de
# política, e quem a relaxar aqui reabre a porta para "o pacote já era assim".
#
# O teto de 80% é orientativo e não entra no gate. Reprovar cobertura alta puniria justamente o
# módulo crítico bem testado; teste que só infla número é achado do review, não daqui.
#
# Prova de medição: sem ela o agente declara `after=75%` sem ter rodado nada, e o gate confere só
# aritmética. Por isso `after` numérico exige (1) um comando de cobertura em `## Comandos
# Executados` e (2) um `log=` existente, dentro do repositório, em que o próprio número de `after`
# aparece. Isso não impede fraude deliberada (o log também pode ser forjado), mas fecha o caminho
# barato de declarar sem medir, no mesmo nível de prova que o log de teste já tem.
#
# `delta` precisa bater com `after - before` (tolerância de 0,1 ponto para arredondamento). Sem
# essa conta, um delta digitado à mão passa com cobertura que caiu.
#
# `after=n/a` só vale quando nenhum arquivo alterado é código executável. A lista de extensões é de
# NÃO-código (allowlist): qualquer extensão fora dela conta como código e exige número, para que
# linguagem nova falhe fechada.

LT_COVERAGE_FLOOR=70

# Ferramentas de cobertura aceitas como prova de medição em `## Comandos Executados`.
LT_COVERAGE_CMD_RE='(-cover|:cov|coverprofile|covermode|--cov|--coverage|coverage (run|report|xml|json)|[^a-z]c8 |[^a-z]nyc |jacoco|kover|tarpaulin|llvm-cov|coverlet|collect:"?xplat code coverage|simplecov|gcovr|lcov|--coverage-)'

# Arquivos alterados declarados no relatório: itens de `## Arquivos Alterados` e valores de campos
# inline `Arquivos alterados: a, b` (formato do relatório de bugfix).
lt_coverage_changed_files() {
  awk '
    /^#+[[:space:]]+Arquivos Alterados/ { capture = 1; next }
    /^#+[[:space:]]/ { capture = 0 }
    capture && /^[[:space:]]*[-*][[:space:]]+/ {
      line = $0; sub(/^[[:space:]]*[-*][[:space:]]+/, "", line); emit(line); next
    }
    tolower($0) ~ /^[[:space:]]*[-*]?[[:space:]]*arquivos alterados[[:space:]]*:/ {
      line = $0; sub(/^[^:]*:[[:space:]]*/, "", line); emit(line)
    }
    function emit(text,   n, parts, i, item) {
      gsub(/`/, "", text)
      n = split(text, parts, "[,[:space:]]+")
      for (i = 1; i <= n; i++) { item = parts[i]; if (item != "") print item }
    }
  ' "$1"
}

# Filtra da lista de arquivos o que é código executável (tudo fora da allowlist de não-código).
lt_coverage_code_files() {
  awk '
    {
      n = split($0, parts, "/"); lower = tolower(parts[n])
      if (lower ~ /^(dockerfile|containerfile|makefile|license|licence|codeowners|notice|authors)([.-].*)?$/) next
      if (lower ~ /^\.(gitignore|gitattributes|dockerignore|editorconfig|prettierrc|nvmrc|tool-versions)$/) next
      if (lower ~ /\.(md|mdx|markdown|txt|rst|adoc|json|jsonc|yaml|yml|toml|ini|cfg|conf|env|example|lock|sum|mod|csv|tsv|png|jpg|jpeg|gif|svg|ico|webp|pdf|tf|tfvars|hcl|sql|proto|graphql|html|css|scss)$/) next
      print $0
    }
  '
}

lt_coverage_check() {
  local report="$1" failed=0 parsed report_dir repo_root line package_name log_path log_value log_abs code_files cmds

  parsed="$(awk -v floor="$LT_COVERAGE_FLOOR" '
    function num(v) { return v ~ /^[+-]?[0-9]+([.][0-9]+)?%$/ }
    function val(v) { sub(/%$/, "", v); return v + 0 }
    /^##[[:space:]]+Coverage[[:space:]]*$/ { capture = 1; next }
    /^##[[:space:]]/ { capture = 0 }
    !capture { next }
    {
      line = $0
      sub(/[[:space:]]+$/, "", line)
      if (line !~ /^(package|before|after|delta|log)=/) next
      key = line; sub(/=.*/, "", key)
      value = line; sub(/^[a-z]+=[[:space:]]*/, "", value)
      if (key == "package") { count++; name[count] = value; next }
      if (count == 0) { print "FALTANDO: " key "= antes de qualquer package= no bloco Coverage"; next }
      field[count, key] = value
    }
    END {
      if (count == 0) { print "FALTANDO: bloco Coverage sem package= (um grupo por pacote tocado, R-TEST-002.1)"; exit }
      for (i = 1; i <= count; i++) {
        p = name[i]
        if (p == "") { print "FALTANDO: package= vazio no bloco Coverage"; continue }
        bad = 0
        for (k = 1; k <= 3; k++) {
          key = (k == 1) ? "before" : (k == 2) ? "after" : "delta"
          if (!((i, key) in field)) { print "FALTANDO: coverage " key " ausente para package=" p " (formato: package=/before=/after=/delta=/log=)"; bad = 1; continue }
          v = field[i, key]
          if (!num(v) && v != "n/a") { print "FALTANDO: coverage " key " inválido para package=" p " (" v ")"; bad = 1 }
        }
        if (bad) continue
        b = field[i, "before"]; a = field[i, "after"]; d = field[i, "delta"]
        if (a == "n/a") {
          if (b != "n/a" || d != "n/a") { print "FALTANDO: after=n/a exige before=n/a e delta=n/a para package=" p; continue }
          print "NA"
          continue
        }
        if (!((i, "log") in field) || field[i, "log"] == "") print "FALTANDO: coverage log= ausente para package=" p " (saída da ferramenta de cobertura que prova after=" a ")"
        else print "LOG\t" p "\t" val(a) "\t" field[i, "log"]
        if (val(a) < floor) printf "FALTANDO: coverage abaixo do piso de %s%% para package=%s (after=%s, R-TEST-002.1)\n", floor, p, a
        if (b == "n/a") {
          if (d != "n/a" && !num(d)) print "FALTANDO: coverage delta inválido para package=" p
          continue
        }
        if (d == "n/a") { print "FALTANDO: coverage delta ausente ou inválido para package=" p " (before medido exige delta numérico)"; continue }
        if (val(d) < 0) printf "FALTANDO: coverage regression detectada para package=%s (delta=%s)\n", p, d
        diff = val(a) - val(b) - val(d)
        if (diff > 0.1 || diff < -0.1) printf "FALTANDO: coverage delta=%s não confere com after-before (%s - %s) para package=%s\n", d, a, b, p
      }
    }
  ' "$report")"

  if printf '%s\n' "$parsed" | grep -q '^FALTANDO:'; then
    printf '%s\n' "$parsed" | grep '^FALTANDO:'
    failed=1
  fi

  report_dir="$(cd "$(dirname "$report")" && pwd)"
  repo_root="$(git -C "$report_dir" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$report_dir")"

  if printf '%s\n' "$parsed" | grep -q '^LOG'; then
    cmds="$(awk '
      /^#+[[:space:]]+Comandos Executados/ { capture = 1; next }
      /^#+[[:space:]]/ { capture = 0 }
      capture { print }
    ' "$report")"
    if ! printf '%s\n' "$cmds" | grep -Eiq -e "$LT_COVERAGE_CMD_RE"; then
      echo "FALTANDO: cobertura declarada sem comando de cobertura em '## Comandos Executados' (prova de medição, R-TEST-002.1)"
      failed=1
    fi
  fi

  while IFS="$(printf '\t')" read -r line package_name log_value log_path; do
    [[ "$line" == "LOG" ]] || continue
    # Só caminho relativo e sem `..`: log fora do repositório não é evidência que acompanha o PR.
    case "$log_path" in
      /*|..|../*|*/../*|*/..)
        echo "FALTANDO: coverage log=$log_path fora do repositório para package=$package_name"
        failed=1
        continue
        ;;
    esac
    log_abs="$repo_root/$log_path"
    [[ -f "$log_abs" ]] || log_abs="$report_dir/$log_path"
    if [[ ! -s "$log_abs" ]]; then
      echo "FALTANDO: coverage log=$log_path inexistente ou vazio para package=$package_name"
      failed=1
      continue
    fi
    if ! awk -v want="$log_value" '
      {
        text = $0
        while (match(text, /[0-9]+([.][0-9]+)?/)) {
          n = substr(text, RSTART, RLENGTH) + 0
          if (n - want <= 0.05 && want - n <= 0.05) { found = 1; exit }
          text = substr(text, RSTART + RLENGTH)
        }
      }
      END { exit !found }
    ' "$log_abs"; then
      echo "FALTANDO: after=${log_value}% de package=$package_name não aparece em log=$log_path (número declarado sem medição)"
      failed=1
    fi
  done <<EOF
$parsed
EOF

  if printf '%s\n' "$parsed" | grep -qx 'NA'; then
    code_files="$(lt_coverage_changed_files "$report" | lt_coverage_code_files)"
    if [[ -z "$(lt_coverage_changed_files "$report")" ]]; then
      echo "FALTANDO: coverage n/a sem arquivos alterados declarados que provem diff sem código executável"
      failed=1
    elif [[ -n "$code_files" ]]; then
      printf 'FALTANDO: coverage n/a com código executável alterado (R-TEST-002.1): %s\n' \
        "$(printf '%s\n' "$code_files" | tr '\n' ' ' | sed -e 's/ $//')"
      failed=1
    fi
  fi

  return "$failed"
}
