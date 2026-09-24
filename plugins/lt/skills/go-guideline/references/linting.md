# Lint em Go

<!-- TL;DR
Conjunto mínimo do Uber (errcheck, goimports, revive, govet, staticcheck) rodado pelo golangci-lint, com a configuração do repo quando existir e o baseline em assets/golangci.yml quando não existir; regras de revive que exigem comentário ficam desligadas por causa de R-STYLE-001.2.
Keywords: golangci-lint, .golangci.yml, errcheck, goimports, gofmt, revive, govet, staticcheck, nolint
Load complete when: a mudança cria ou altera configuração de lint, ou a validação precisa interpretar achado de linter.
-->

- Escopo: validação estática de código Go.
- Fonte: Uber, seção "Linting".

## GO-LINT-001 Conjunto mínimo

Uber: mais importante que qualquer lista "abençoada" é rodar lint **de forma consistente** no
código inteiro. O mínimo recomendado:

| Linter | O que pega |
|---|---|
| `errcheck` | Erro devolvido e ignorado. |
| `goimports` | Formatação e grupos de import. |
| `revive` | Erros comuns de estilo. É o sucessor do `golint`, que foi descontinuado. |
| `govet` | Erros comuns: formato de `Printf`, cópia de lock, `cancel` perdido, sombreamento. |
| `staticcheck` | Análise estática ampla: bugs, código morto, API obsoleta. |

O runner recomendado é o `golangci-lint`. O time pode acrescentar linters além desse mínimo.

## GO-LINT-002 Qual configuração usar

1. Se o repo tem `.golangci.yml` ou `.golangci.yaml`, use essa configuração. Não troque a
   configuração do time sem pedido.
2. Se não tem, proponha o baseline de `assets/golangci.yml` desta skill. Ele segue o formato v2 do
   golangci-lint, com o mínimo do Uber e as regras do revive que exigem comentário desligadas.
3. Confira a configuração com `golangci-lint config verify` antes de rodar.

Por que as regras `exported` e `package-comments` do revive ficam desligadas no baseline: elas
exigem doc-comment em todo símbolo exportado, e `R-STYLE-001.2` proíbe comentário no código
produzido pelas skills. Se o repo do time exige doc-comment e o próprio time mantém essa
configuração, vale a configuração do repo.

## GO-LINT-003 Achado de linter

- Corrija a causa. Não silencie.
- `//nolint:<linter>` é diretiva lida pelo runner, com o linter sempre nomeado e nunca um
  `//nolint` genérico. Só entra se a pessoa aceitar a exceção. O motivo vai no relatório ou no PR,
  não em comentário no código (`R-STYLE-001.2`).
- `_ = f()` para ignorar erro só quando ignorar é comprovadamente correto, como no `Close` de um
  leitor já consumido. Nunca em escrita, commit ou `Close` de escrita, em que o erro indica perda de
  dado.

## GO-LINT-004 Ordem de execução

```bash
gofmt -l .
go vet ./...
golangci-lint run ./...
```

- Sem `golangci-lint` instalado, rode `staticcheck ./...` e reporte a ausência do runner.
- Ferramenta que não pôde rodar é reportada como `não verificado`, nunca como aprovada.
