#!/usr/bin/env bash
# tests / enterprise / codex-requirements.sh — a politica do Codex proibe o bypass de sandbox.
#
# Comportamento do Codex provado em container (0.156.1, docs/host-facts.md): com este arquivo em
# /etc/codex/requirements.toml, --dangerously-bypass-approvals-and-sandbox e danger-full-access sao
# recusados antes de qualquer chamada ao modelo. Aqui se prova o PAYLOAD e o caminho do verify.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REQ="$REPO/enterprise/codex-requirements.toml"
OK=0; BAD=0
ok()  { OK=$((OK+1));  printf '  ✓ %s\n' "$1"; }
bad() { BAD=$((BAD+1)); printf '  ✗ %s\n' "$1" >&2; }

printf '\n▸ codex-requirements\n'
python3 - "$REQ" <<'PY' && ok "TOML valido, sem danger-full-access, com workspace-write" || bad "payload permissivo ou invalido"
import sys, tomllib
d = tomllib.load(open(sys.argv[1], "rb"))
modes = d.get("allowed_sandbox_modes") or []
sys.exit(0 if "danger-full-access" not in modes and "workspace-write" in modes else 1)
PY
grep -q 'Politica gerenciada do Codex CLI da Lima Teixeira' "$REQ" \
  && ok "marcador que o uninstall usa para nao apagar politica alheia" || bad "marcador ausente"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
printf 'allowed_sandbox_modes = ["danger-full-access"]\n' > "$T/bad.toml"
LT_VERIFY_TARGET="$REPO/enterprise/managed-settings.json" LT_VERIFY_CODEX_TARGET="$T/bad.toml" \
  bash "$REPO/enterprise/verify.sh" >/dev/null 2>&1 \
  && bad "verify aceitou politica permissiva" || ok "verify reprova politica permissiva"
printf '  %d ok · %d falha\n' "$OK" "$BAD"
[ "$BAD" -eq 0 ]
