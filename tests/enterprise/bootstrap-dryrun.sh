#!/usr/bin/env bash
# tests / enterprise / bootstrap-dryrun.sh — o bootstrap roda sem sudo e sem rede.
#
# `skip` aqui e' CONTADO, nunca verde: sem `gh` o caminho real nao foi exercitado, e dizer
# "passou" seria mentir sobre o que foi testado.

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OK=0; BAD=0; SKIP=0
ok()   { OK=$((OK+1));   printf '  ✓ %s\n' "$1"; }
bad()  { BAD=$((BAD+1)); printf '  ✗ %s\n' "$1" >&2; }
skip() { SKIP=$((SKIP+1)); printf '  ~ %s (pulado: %s)\n' "$1" "$2"; }

printf '\n▸ bootstrap-dryrun\n'
for f in bootstrap-mac.sh bootstrap-linux.sh; do
  if LT_DRYRUN=1 bash "$REPO/enterprise/$f" >/dev/null 2>&1; then
    ok "$f roda em dry-run sem sudo"
  else
    bad "$f falhou em dry-run"
  fi
done

if command -v pwsh >/dev/null 2>&1; then
  LT_DRYRUN=1 pwsh -File "$REPO/enterprise/bootstrap-windows.ps1" >/dev/null 2>&1 \
    && ok "bootstrap-windows.ps1 roda em dry-run" || bad "bootstrap-windows.ps1 falhou"
else
  skip "bootstrap-windows.ps1" "pwsh ausente"
fi

# O caminho do Windows e' o oficial, nao o legado que o host NAO le.
if grep -q 'C:\\Program Files\\ClaudeCode' "$REPO/enterprise/bootstrap-windows.ps1"; then
  ok "Windows aponta para 'Program Files' (caminho oficial)"
else
  bad "Windows nao usa o caminho oficial"
fi
if grep -q '\$Dest.*ProgramData' "$REPO/enterprise/bootstrap-windows.ps1"; then
  bad "Windows instala em ProgramData, que o Claude Code NAO le"
else
  ok "nao instala no caminho legado ProgramData"
fi

LT_VERIFY_TARGET="$REPO/enterprise/managed-settings.json" LT_VERIFY_CODEX_TARGET="$REPO/enterprise/codex-requirements.toml" bash "$REPO/enterprise/verify.sh" >/dev/null 2>&1 \
  && ok "verify.sh passa contra o payload do repo" || bad "verify.sh reprovou o payload do repo"

printf '  %d ok · %d falha · %d pulado\n' "$OK" "$BAD" "$SKIP"
[ "$BAD" -eq 0 ]
