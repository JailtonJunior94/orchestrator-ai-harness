#!/usr/bin/env bash
# Versao ativa do harness. Durante a migracao da frota, e' assim que a pessoa sabe qual roda.
set -uo pipefail
[ -n "${LT_VERSION:-}" ] && printf 'lt %s' "$LT_VERSION"
