#!/usr/bin/env bash
# scripts / validate-playbook-counts.sh
#
# Guarda toda contagem escrita em prosa ("Onze hooks", "21 skills") contra o disco.
#
# POR QUE EXISTE
# Contagem em prosa sem teste que a cruze com `ls` envelhece em silencio: uma skill entra, o
# README continua dizendo o numero antigo, e prosa que mente e' pior que prosa ausente. Por isso
# o README se proibia de exibir contagem enquanto este script nao existisse.
#
# AS DUAS FORMAS DE AFIRMACAO
# 1. Total ("Onze hooks", "21 skills", "4 commands"): comparado com o disco.
# 2. Lista ("Onze skills: `a → b → c`, mais `d`"): comparada com o numero de nomes em backtick
#    que a propria frase enumera, ate' o fim do paragrafo. Uma contagem de subconjunto nao pode
#    ser conferida contra o total, mas pode ser conferida contra a lista que ela afirma contar.
#
# Uso:  bash scripts/validate-playbook-counts.sh [arquivo.md ...]
# Sem argumentos, confere a lista fixa PROSE_FILES de scripts/lib/check-plugin-counts.py
# (README, CLAUDE.md, guia, docs de governanca, READMEs de plugin e enterprise) mais as
# `description` do plugin.json e do marketplace.json.
#
# O motor mora em scripts/lib/check-plugin-counts.py; este script e' so' a porta em shell, para
# que CI, pilot-check e docs-generated-fresh continuem chamando o mesmo nome.
# Exit: 0 tudo confere · 1 alguma contagem diverge · 2 uso invalido

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

exec python3 "$ROOT/scripts/lib/check-plugin-counts.py" --root "$ROOT" "$@"
