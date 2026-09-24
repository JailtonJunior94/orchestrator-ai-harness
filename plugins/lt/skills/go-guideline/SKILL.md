---
name: go-guideline
description: Diretrizes de produção para código Go, com o Uber Go Style Guide como fonte mandatória (erros, goroutines, context, interfaces, testes, desempenho e lint). Use sempre que for escrever, revisar, refatorar ou avaliar se um arquivo .go, go.mod ou _test.go está pronto para produção, mesmo que o pedido não cite Go nem Uber. Não use para outras linguagens nem para arquitetura sem código Go.
metadata:
  version: 1.0.0
  category: language
---

# Diretrizes Go

Piso de qualidade para código Go que vai para produção. As regras vêm do
[Uber Go Style Guide](https://github.com/uber-go/guide/blob/master/style.md) (Apache-2.0). Nos
temas que o Uber não cobre (context, generics, fuzz, profiling), as regras vêm da documentação
oficial do Go.

## Precedência

A ordem abaixo resolve qualquer conflito entre regras:

1. A constitution do harness (`R-STYLE-001`, `R-SEC`, `R-ERR`): regra hard vence qualquer fonte externa.
2. O Uber Go Style Guide.
3. A documentação oficial do Go (Effective Go, Go Code Review Comments, notas de release).
4. A convenção já estabelecida no repositório, desde que não contradiga os itens acima. O Uber
   manda priorizar consistência: aplique mudança de estilo no pacote inteiro ou em nada.

### Exceções ao Uber

Cada exceção tem motivo registrado. Fora desta tabela, o Uber vale literalmente.

| Regra do Uber | O que vale aqui | Motivo |
|---|---|---|
| Prefixo `_` em globais não exportadas (`_defaultPort`) | Sem prefixo: `defaultPort` | `R-STYLE-001.3` proíbe `_` em identificador. |
| Comentário em parâmetro nu (`/* isLocal */`) e doc-comment nos exemplos | Tipo nomeado no lugar do `bool` nu; nenhum comentário no código produzido | `R-STYLE-001.2` proíbe comentário no código produzido. O próprio Uber recomenda o tipo nomeado como opção melhor. |
| `go.uber.org/atomic` | `sync/atomic` tipado (`atomic.Bool`, `atomic.Int64`) quando `go.mod` declara Go 1.19 ou superior | O motivo do Uber é segurança de tipo, e a stdlib passou a oferecer os mesmos tipos no Go 1.19. Abaixo disso, vale o Uber. |
| Cópia `tt := tt` antes de `t.Parallel()` | Sem a cópia quando `go.mod` declara Go 1.22 ou superior | O Go 1.22 passou a criar uma variável por iteração no `for`. Abaixo disso, a cópia é obrigatória. |

## Piso inegociável

Toda mudança em Go cumpre estas regras, sem precisar abrir nenhuma referência:

1. Erro é tratado **uma vez**: ou retorna com contexto, ou loga e degrada. Nunca loga e retorna o mesmo erro.
2. Contexto de erro é curto e sem "failed to": `fmt.Errorf("get user %q: %w", id, err)`.
3. Sem `panic` em código de produção. `os.Exit` e `log.Fatal` só em `main()`, de preferência uma vez, com a lógica em `run() error`.
4. Asserção de tipo sempre com comma-ok: `v, ok := x.(T)`.
5. Toda goroutine tem forma previsível de parar e alguém que espera o fim dela. Nenhuma goroutine em `init()`.
6. Canal com buffer 0 ou 1. Qualquer outro tamanho exige justificativa de como ele não enche sob carga.
7. Mutex como valor (`mu sync.Mutex`), nunca ponteiro e nunca embutido.
8. Slice e map recebidos ou devolvidos na fronteira da API são copiados quando o tipo guarda ou expõe o estado interno.
9. Sem estado global mutável: dependências entram por injeção. `init()` só nos casos que o Uber aceita.
10. Sem ponteiro para interface. Sem embutir tipo em struct pública.
11. Struct serializada (JSON, YAML) tem tag em todo campo.
12. `time.Time` para instante e `time.Duration` para período, inclusive na fronteira com outros sistemas.

## Referências

Abra só a referência que a mudança exige. Para descobrir quais casam com o diff (`AGENTS_ROOT` é o
diretório que contém `skills/`, dois níveis acima desta skill em qualquer host):

```bash
git diff | AGENTS_ROOT="${CLAUDE_SKILL_DIR}/../.." bash "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-references.sh" go-guideline <arquivos tocados>
```

| Tarefa | Referência |
|---|---|
| Criar, embrulhar, comparar ou logar erro; `panic`; saída do programa | `references/errors.md` |
| Goroutine, canal, mutex, atomic, errgroup, worker | `references/concurrency.md` |
| Cancelamento, timeout, `context.Context` em assinatura | `references/context.md` |
| Interface, receiver, embedding, functional options, enum, tempo, generics | `references/api-design.md` |
| Nomes, imports, declarações, inicialização, `init()`, globais, legibilidade | `references/style.md` |
| Table test, subtest, paralelismo, race, vazamento de goroutine, fuzz, benchmark | `references/testing.md` |
| Caminho quente, alocação, profiling | `references/performance.md` |
| golangci-lint, gofmt, goimports, vet, staticcheck, revive | `references/linting.md` |

## Procedimentos

**Etapa 1: Ler o contexto do módulo**
1. Ler `go.mod` e anotar a versão declarada na diretiva `go`. Ela decide as exceções de atomic e
   `tt := tt` e quais recursos da linguagem podem ser usados (`wg.Go` exige Go 1.25; `b.Loop`, Go 1.24).
2. Sem `go.mod` acessível, não presumir versão: usar só construções válidas desde o Go 1.21 e
   registrar a suposição.
3. Ler a configuração de lint do repo (`.golangci.yml` ou `.golangci.yaml`), se existir. A ausência
   é achado a reportar, não motivo para inventar uma.

**Etapa 2: Carregar as regras certas**
1. Aplicar o piso inegociável sempre.
2. Rodar o `resolve-references.sh` acima e abrir apenas as referências listadas. Se o script não
   estiver disponível, escolher pela tabela de referências.

**Etapa 3: Implementar**
1. Escrever a menor mudança que resolve o pedido, seguindo as referências carregadas.
2. Código, identificadores, mensagens de erro e de log em inglês (`R-STYLE-001.1`).
3. Não adicionar dependência externa para algo que a stdlib já resolve.

**Etapa 4: Validar**

Rodar, nesta ordem, os comandos que existirem no ambiente:

```bash
gofmt -l .
go vet ./...
golangci-lint run ./...
go test -race ./...
```

1. Se `golangci-lint` não estiver instalado, rodar `staticcheck ./...` e reportar a ausência do runner.
2. Comando que não pôde rodar é reportado como `não verificado`, com o motivo. Nunca é reportado como aprovado.
3. Falha é reportada com o comando exato e a primeira mensagem relevante.

**Etapa 5: Revisar a própria mudança**
1. Conferir o diff contra o piso inegociável.
2. Registrar cada desvio intencional de uma regra com o ID (`GO-ERR-003`, por exemplo) e o motivo.

## Tratamento de Erros

- Pedido que exige violar o piso (por exemplo, "loga e retorna o erro"): explicar a regra, propor
  a alternativa conforme e só seguir o pedido original se a pessoa confirmar.
- Regra do repo que contradiz o Uber: seguir o repo **no arquivo tocado**, apontar a divergência
  no relatório e não reescrever o resto do pacote por conta própria.
- Dúvida sobre API da stdlib ou de biblioteca: consultar `go doc <pacote>.<símbolo>` localmente
  antes de afirmar comportamento.

## Atribuição

As regras marcadas com `Uber:` nas referências são adaptadas do
[uber-go/guide](https://github.com/uber-go/guide), licenciado sob Apache License 2.0. A tradução e
as exceções acima são deste harness.
