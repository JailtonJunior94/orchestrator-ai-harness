#!/usr/bin/env bash
# tests / enterprise / run.sh — banner por arquivo: "✓ pass"
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAIL=0
for f in version-pin managed-settings-schema bootstrap-dryrun codex-requirements; do
  if bash "$HERE/$f.sh"; then printf '✓ pass %s\n' "$f"
  else printf '✗ fail %s\n' "$f" >&2; FAIL=1; fi
done
printf '\n'
[ "$FAIL" -eq 0 ] && { printf 'ENTERPRISE PASSOU\n'; exit 0; }
printf 'ENTERPRISE FALHOU\n' >&2; exit 1
