#!/usr/bin/env bash
set -uo pipefail
command -v git >/dev/null 2>&1 || exit 0
cd "${LT_PROJECT:-$PWD}" 2>/dev/null || exit 0
B="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
[ -n "$B" ] && [ "$B" != "HEAD" ] && printf '%s' "$B"
