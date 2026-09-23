#!/usr/bin/env bash
# tests / unit / scripts / bash32-empty-array.test.sh
#
# `"${arr[@]}"` com array VAZIO e' `unbound variable` sob `set -u` no bash 3.2 — o /bin/bash dos
# Macs da frota. Em bash 4.4+ a mesma linha e' silenciosa. E' a classe de defeito mais cara deste
# repo, e o guard existente NAO a cobria: `config/bash32-forbidden.txt` lista construcoes de
# bash 4+ (`mapfile`, `declare -A`, `${v,,}`), e esta e' a classe INVERSA — sintaxe valida nas duas
# versoes, comportamento diferente. `bash -n` tambem nao pega: e' erro de runtime, nao de sintaxe.
#
# Encontrado rodando um comando sem argumento: a expansão de array vazia morria em
# `rest[@]: unbound variable`. Havia mais 13 ocorrencias latentes em cinco outros scripts.
#
# As quatro formas falham igual no 3.2 — `for`, `printf`, argumento de funcao e atribuicao.
# O idioma portavel e' `${arr[@]+"${arr[@]}"}`: expande para nada quando vazio, para os elementos
# quando ha' algum, e funciona em 3.2 e em 4+.
#
# POR QUE A REGRA E' ESTREITA. Sinalizar todo `"${arr[@]}"` produziria falso positivo em array
# provadamente nao-vazio. Este gate so' acusa quando as TRES condicoes valem juntas:
#   1. o arquivo usa `set -u` (sem isso, a expansao vazia e' inocua);
#   2. o array e' inicializado vazio (`nome=()`) no proprio arquivo, logo PODE estar vazio;
#   3. a expansao nao usa a guarda `[@]+`.
# Linha de comentario e' ignorada — comentario nao executa, e um guard que casa a propria
# documentacao e' como tres guards deste harness nasceram quebrados.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
. "$REPO/tests/unit/lib/assert.sh"

describe "bash 3.2 — expansao de array vazio sob set -u"

# Confirma que a premissa do gate ainda vale nesta maquina. Se o /bin/bash subir para 4.4+, o
# gate continua correto para a frota, mas esta asserção deixa de ser representativa e diz isso.
V="$(/bin/bash --version | head -1)"
case "$V" in
  *"version 3."*)
    if /bin/bash -c 'set -u; a=(); f(){ :; }; f "${a[@]}"' 2>/dev/null; then
      bad "premissa falhou: /bin/bash 3.x aceitou expansao de array vazio sob set -u"
    else
      ok "premissa confirmada: /bin/bash 3.x recusa \"\${a[@]}\" com array vazio"
    fi
    if /bin/bash -c 'set -u; a=(); f(){ :; }; f ${a[@]+"${a[@]}"}' 2>/dev/null; then
      ok "o idioma guardado funciona em 3.x"
    else
      bad "o idioma guardado \${a[@]+...} falhou em 3.x — a correcao proposta nao serve"
    fi
    ;;
  *) skip "premissa de runtime" "/bin/bash desta maquina nao e' 3.x ($V)" ;;
esac

OUT="$(cd "$REPO" && python3 - <<'PY'
import os, re, io
RE_SETU  = re.compile(r'^set -[a-z]*u|^set -o nounset', re.M)
RE_EMPTY = re.compile(r'^\s*(?:local\s+)?([A-Za-z_][A-Za-z0-9_]*)=\(\)\s*$', re.M)
RE_USE   = re.compile(r'"\$\{([A-Za-z_][A-Za-z0-9_]*)\[@\]\}"')

for root, dirs, files in os.walk('.'):
    if '.git' in root:
        continue
    for fn in sorted(files):
        if not fn.endswith('.sh'):
            continue
        path = os.path.join(root, fn)
        text = io.open(path, encoding='utf-8', errors='replace').read()
        if not RE_SETU.search(text):
            continue
        empties = set(RE_EMPTY.findall(text))
        if not empties:
            continue
        for lineno, line in enumerate(text.split('\n'), 1):
            if line.lstrip().startswith('#') or '[@]+' in line:
                continue
            for m in RE_USE.finditer(line):
                if m.group(1) in empties:
                    print("%s:%d [%s]" % (path[2:], lineno, m.group(1)))
PY
)"

if [ -n "$OUT" ]; then
  while IFS= read -r l; do
    [ -n "$l" ] && bad "expansao desprotegida: $l"
  done <<EOF
$OUT
EOF
else
  ok "nenhuma expansao de array possivelmente vazio sem a guarda \${arr[@]+...}"
fi

end_describe
