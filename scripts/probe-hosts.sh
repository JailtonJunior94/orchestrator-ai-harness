#!/usr/bin/env bash
# scripts / probe-hosts.sh — banner: HOSTS PROVADOS
#
# Sonda dos quatro hosts SEM modelo e SEM credencial: instala a projecao global do harness num HOME
# descartavel e pergunta a cada CLI o que ele carregou. Existe porque os formatos de Codex, Copilot
# e OpenCode nao sao contrato publicado: mudam entre versoes, e a mudanca desliga a governanca em
# silencio (o Codex pula hook sem trusted_hash valido sem nenhum aviso).
#
# O que prova, por CLI presente:
#   claude   plugin validate do plugin lt
#   codex    skills do harness no prompt (debug prompt-input); config.toml aceito (--strict-config
#            chega ao 401 de autenticacao, nao ao erro de config)
#   opencode skills (debug skill), agents (agent list) e plugin lt-governance.js (debug config)
#   copilot  skills (skill list)
# CLI ausente e' `skip` CONTADO, nunca verde silencioso. Com --require-tested, versao fora de
# config/host-versions.json reprova: e' o aviso de que os fatos de host precisam ser re-provados.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REQUIRE_TESTED=0
[ "${1:-}" = "--require-tested" ] && REQUIRE_TESTED=1

OK=0; BAD=0; SKIP=0
ok()   { OK=$((OK+1));   printf '  ✓ %s\n' "$1"; }
bad()  { BAD=$((BAD+1)); printf '  ✗ %s\n' "$1" >&2; }
skip() { SKIP=$((SKIP+1)); printf '  ~ %s (pulado: %s)\n' "$1" "$2"; }

W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
export HOME="$W/home" CODEX_HOME="$W/home/.codex" COPILOT_HOME="$W/home/.copilot" \
       XDG_CONFIG_HOME="$W/home/.config" LT_RUNTIME_HOME="$W/home/.lt-harness"
mkdir -p "$HOME" "$W/proj"
( cd "$W/proj" && git init -q ) 2>/dev/null

printf '\n▸ projecao global num HOME descartavel\n'
if python3 "$REPO/plugins/lt/scripts/reconcile-hosts.py" install --scope global --hosts codex,copilot,opencode >/dev/null 2>&1; then
  ok "reconcile-hosts install --scope global"
else
  bad "reconcile-hosts install --scope global falhou"
fi

# Saida de CLI vai para arquivo e o parse e' feito depois: grep direto no pipe deu falso negativo
# nas sondas manuais (saida bufferizada/truncada pelo timeout).
run_to() { local out="$1"; shift; ( cd "$W/proj" && timeout 90 "$@" </dev/null >"$out" 2>&1 ); return 0; }
has_all() { local f="$1"; shift; local n; for n in "$@"; do grep -q -- "$n" "$f" || return 1; done; return 0; }

version_ok() {  # $1=host $2=versao
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if sys.argv[3] in d.get(sys.argv[2],[]) else 1)' \
    "$REPO/config/host-versions.json" "$1" "$2"
}
check_version() {  # $1=host $2=versao
  if version_ok "$1" "$2"; then ok "$1 $2 esta entre as versoes provadas"
  elif [ "$REQUIRE_TESTED" -eq 1 ]; then bad "$1 $2 NAO foi provado (config/host-versions.json): re-prove os fatos de docs/host-facts.md"
  else printf '  ! %s %s nao foi provado — rode as sondas vivas antes de confiar\n' "$1" "$2"; fi
}

printf '\n▸ claude\n'
if command -v claude >/dev/null 2>&1; then
  V="$(claude --version 2>/dev/null | head -1 | cut -d' ' -f1)"; check_version claude "$V"
  claude plugin validate "$REPO/plugins/lt" >"$W/cv" 2>&1 && ok "plugin validate" || bad "plugin validate: $(tail -1 "$W/cv")"
else skip "claude" "CLI ausente"; fi

printf '\n▸ codex\n'
if command -v codex >/dev/null 2>&1; then
  V="$(codex --version 2>/dev/null | awk '{print $NF}')"; check_version codex "$V"
  run_to "$W/cx" codex debug prompt-input oi
  has_all "$W/cx" using-lt create-prd execute-task && ok "skills do harness no prompt" || bad "skills do harness ausentes do prompt do Codex"
  run_to "$W/cs" codex exec --strict-config --skip-git-repo-check oi
  if grep -qiE 'unauthorized|401|log ?in|auth' "$W/cs" && ! grep -qE '^ *[0-9]+ \| ' "$W/cs"; then
    ok "config.toml aceito sob --strict-config"
  else bad "config.toml rejeitado: $(head -3 "$W/cs" | tr '\n' ' ' | cut -c1-160)"; fi
else skip "codex" "CLI ausente"; fi

printf '\n▸ opencode\n'
if command -v opencode >/dev/null 2>&1; then
  V="$(opencode --version 2>/dev/null | tail -1)"; check_version opencode "$V"
  run_to "$W/os" opencode debug skill
  has_all "$W/os" using-lt create-prd execute-task && ok "skills" || bad "skills do harness ausentes no OpenCode"
  run_to "$W/oa" opencode agent list
  has_all "$W/oa" task-executor reviewer && ok "agents" || bad "agents do harness ausentes no OpenCode"
  run_to "$W/oc" opencode debug config
  has_all "$W/oc" lt-governance.js && ok "plugin lt-governance.js carregado" || bad "plugin de governanca ausente no OpenCode"
else skip "opencode" "CLI ausente"; fi

printf '\n▸ copilot\n'
if command -v copilot >/dev/null 2>&1; then
  V="$(copilot --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"; check_version copilot "$V"
  run_to "$W/ps" copilot skill list
  has_all "$W/ps" using-lt create-prd execute-task && ok "skills" || bad "skills do harness ausentes no Copilot"
  skip "copilot agents" "listar agents exige login (--agent), fora do escopo sem credencial"
else skip "copilot" "CLI ausente"; fi

printf '\n───────────────────────────────\n%d ok · %d falha · %d pulado\n' "$OK" "$BAD" "$SKIP"
[ "$BAD" -eq 0 ] && { printf 'HOSTS PROVADOS\n'; exit 0; }
printf 'HOSTS COM FALHA\n' >&2; exit 1
