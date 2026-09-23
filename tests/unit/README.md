# Testes unitários

`tests/unit/run.sh` descobre por `find` e roda todo `*.test.sh` sob `tests/unit/`. Não há lista
fixa: teste novo que ninguém lembrou de registrar ficaria verde por ausência. Zero testes
descobertos é **erro**, não sucesso. Banner de sucesso: `Suite unit passou (N arquivos)`.

```bash
bash tests/unit/run.sh                                        # tudo
bash tests/unit/scripts/statusline-provision.test.sh          # um arquivo
/bin/bash tests/unit/run.sh                                   # no bash 3.2 do macOS, como no CI
```

## Onde cada teste mora

| Diretório | Cobre |
|---|---|
| `hooks/` | comportamento dos hooks com o payload do host |
| `lib/` | resolvedores de `plugins/lt/lib/` (guarda destrutiva, caminhos sensíveis), com casos em `tests/fixtures/` |
| `scripts/` | scripts de `scripts/` e de `plugins/lt/scripts/`: instalador, provisionador de statusline, bump, ratchets, motor do ciclo SDD |

## O helper `lib/assert.sh`

Bash puro, sem framework externo: o harness precisa testar a si mesmo num macOS com bash 3.2 e
nenhuma dependência instalada.

| Função | Uso |
|---|---|
| `describe "<texto>"` | abre um bloco |
| `ok` / `bad` / `skip "<o quê>" "<motivo>"` | contadores diretos |
| `assert_eq <esperado> <obtido> [msg]` · `assert_ne` | igualdade |
| `assert_contains <texto> <trecho> [msg]` · `assert_not_contains` | substring |
| `assert_exit_code <n> <comando…>` | código de saída |
| `assert_file_exists <caminho> [msg]` | presença |
| `assert_not_scratchpad` | falha se `HOME` ou `CLAUDE_CONFIG_DIR` apontam para fora de diretório temporário |
| `end_describe` | imprime o placar e devolve 1 se houve `bad` — use como última linha |

## Regras

1. **`skip` não é `fail`, e também não é `pass`.** Dependência ausente vira `skip "<o quê>"
   "<motivo>"`, contado à parte. Um `skip` que soma em verde transforma "a ferramenta sumiu" em
   "tudo certo".
2. **Ambiente isolado, os dois.** Todo teste que escreve estado exporta `HOME` **e**
   `CLAUDE_CONFIG_DIR` para um `mktemp -d` e chama `assert_not_scratchpad` antes de qualquer
   escrita. Isolar só o `HOME` já deixou um teste gravar linhas falsas no audit trail real — e
   passar verde, porque as linhas que ele criou satisfaziam as próprias asserções.
3. **Limpeza por `trap`.** `W="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$W"' EXIT`.
4. **Positivo e negativo.** Guarda testada só no caminho feliz não prova que guarda.
5. **Regressão falha contra o código antigo.** Antes do PR, rode o teste novo contra a versão
   sem o fix e confirme que ele reprova.
6. **Sem data relativa nem rede.** Data relativa passa no macOS e falha no Linux; rede torna o
   teste não determinístico. Saída de CLI externo entra por arquivo gravado (ver
   `LT_DETAILS_OUTPUT` em `tests/unit/scripts/cost-baseline.test.sh`).
7. **bash 3.2.** As mesmas regras do `CLAUDE.md` §2 valem aqui: sem `mapfile`, sem `declare -A`,
   expansão de array guardada sob `set -u`.

## Esqueleto

```bash
#!/usr/bin/env bash
# tests / unit / <area> / <nome>.test.sh
#
# <o que este teste protege, e o defeito que ele impede de voltar>

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
. "$REPO/tests/unit/lib/assert.sh"

W="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$W"' EXIT
export HOME="$W/home" CLAUDE_CONFIG_DIR="$W/home/.claude"
mkdir -p "$CLAUDE_CONFIG_DIR"

describe "isolamento"
assert_not_scratchpad || { end_describe; exit 1; }

describe "<comportamento>"
assert_eq "esperado" "$(comando)" "descrição do que foi provado"

end_describe
```
