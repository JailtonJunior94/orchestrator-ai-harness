#!/usr/bin/env bash
set -uo pipefail
IN="$(cat 2>/dev/null)"
M="$(printf '%s' "$IN" | sed -n 's/.*"display_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
[ -n "$M" ] || M="$(printf '%s' "$IN" | sed -n 's/.*"model"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
[ -n "$M" ] && printf '%s' "$M"
