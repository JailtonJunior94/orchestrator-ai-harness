---
name: domain-modeling
description: Modela o domínio com tipos no estilo Domain Modeling Made Functional (linguagem ubíqua, estados ilegais irrepresentáveis, workflows como pipelines, erros como Result) e traduz o modelo para a linguagem do repositório. Use antes da techspec ou ao desenhar e revisar agregados, estados, eventos e regras de negócio. Não use para estilo de uma linguagem nem para escrever PRD.
metadata:
  version: 1.0.0
  category: processual
---

# Modelagem de Domínio Funcional

Transforma regra de negócio em tipos que tornam o estado inválido impossível de construir e em
workflows que deixam explícito o que entra, o que sai e o que pode falhar. O modelo é escrito numa
notação agnóstica e depois traduzido para a linguagem do repositório.

## Precedência

1. A constitution do harness (`R-STYLE-001`, `R-SEC`, `R-ERR`): regra hard vence qualquer fonte.
2. `R-DDD-001` (`lt:agent-governance, referencia ddd.md`): regras de código para entidade,
   value object e aggregate root.
3. Os princípios de *Domain Modeling Made Functional* resumidos nas referências desta skill.
4. A convenção já estabelecida no repositório, quando não contradiz os itens acima.

## Piso inegociável

1. Conceito com regra própria não circula como primitivo nu: vira tipo restrito com construtor que
   valida e devolve erro.
2. Estado do ciclo de vida é tipo próprio (`PedidoNaoValidado`, `PedidoValidado`), nunca flag,
   booleano ou string de status comparada no código.
3. Alternativa de negócio é escolha exaustiva (`A OR B`), e todo consumidor trata cada caso.
4. Comando expressa intenção e pode falhar. Evento expressa fato consumado e não falha.
5. Workflow tem assinatura `Comando -> Result<Eventos, ErroDeDominio>`, com dependências
   declaradas como parâmetros.
6. Erro de domínio é tipado e nomeado pelo negócio, separado de erro de infraestrutura.
7. I/O, relógio, aleatoriedade e persistência ficam nas bordas, fora do núcleo do domínio.
8. DTO, schema de fila e tabela existem só na fronteira; o tipo de domínio não carrega tag de
   serialização nem de ORM.
9. Novo contexto, agregado, evento ou estado só entra com ganho declarado de clareza,
   robustez ou custo.
10. Nenhum fato sem evidência: comportamento existente cita `path:linha`; o que não foi confirmado
    vai para `Itens em Aberto`, nunca para o modelo como certeza.

## Referências

Abra só a referência que a etapa exige.

| Tarefa | Referência |
|---|---|
| Decidir o que modelar, detectar modelo fraco | `references/principles.md` |
| Escrever tipos, escolhas, tipos restritos e assinaturas | `references/type-notation.md` |
| Desenhar pipeline, eventos, dependências e erros | `references/workflows-and-errors.md` |
| Bounded context, DTO, ACL, serialização, persistência, evolução | `references/boundaries-and-persistence.md` |
| Traduzir o modelo para Go, TypeScript, Python, Java, Kotlin ou C# | `references/translation.md` |
| Conferir se o modelo está pronto para handoff | `references/quality-gates.md` |

> **Camada de linguagem é opcional.** Go tem a skill `lt:go-guideline`; as de Node, Python e .NET
> não vêm nesta versão do plugin. Antes de mandar carregar qualquer uma, **verifique o que existe**:
>
> ```bash
> bash "${CLAUDE_PLUGIN_ROOT}/scripts/lt-sdd.sh" skills-available --category language
> ```
>
> Linguagem cuja skill não aparece na saída segue só com `references/translation.md`, e você diz
> isso à pessoa.

## Procedimentos

**Etapa 1: Detectar o modo**
1. `modelar`: o pedido descreve um fluxo, uma capacidade ou um PRD a modelar.
2. `revisar`: o pedido aponta código de domínio existente para avaliar ou corrigir.
3. Se o pedido não permitir decidir, perguntar uma vez com as duas opções.

**Etapa 2: Resolver o destino e ler a entrada**
1. Com PRD, resolver o bundle com
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/lt-sdd.sh" specs-root --slug <slug> --create` e gravar o modelo em
   `<bundle>/domain-model.md`. Nunca montar o caminho à mão.
2. Sem PRD, gravar onde a pessoa indicar; sem indicação, perguntar antes de criar arquivo.
3. Extrair do PRD os `RF-NN`, as restrições e o que está fora de escopo. Cada workflow modelado
   cita os `RF-NN` que atende.

**Etapa 3: Confrontar com o codebase**
1. Buscar termos do domínio, enums, status, erros, validações, eventos e tabelas relacionadas.
2. Classificar cada achado como `confirmado`, `suspeito`, `ausente` ou `greenfield`.
3. `confirmado` exige `path:linha` de código de produção. Achado só em teste, mock, fixture,
   exemplo, documentação ou arquivo gerado fica `suspeito`.
4. Sem acesso ao código, declarar `greenfield` ou registrar o confronto como não realizado.

**Etapa 4: Esclarecer só o que é material**
1. Material é o que muda um tipo, uma transição, um erro, uma fronteira ou um evento. O resto é
   decidido, registrado como suposição e segue.
2. Aplicar `lt:agent-governance, referencia multiple-choice-protocol.md`: uma pergunta por turno,
   2 a 5 opções, a primeira marcada "(Recomendado)".
3. Resposta que a pessoa não sabe dar vira item em `Itens em Aberto` com o impacto no modelo.
   Se faltar linguagem ubíqua, invariante central ou erro de domínio do fluxo principal, encerrar
   com `needs_input`.

**Etapa 5: Modelar**
1. Ler `references/principles.md` e `references/type-notation.md`.
2. Fixar a linguagem ubíqua: termo canônico, definição e sinônimos proibidos.
3. Escrever os tipos: simples restritos, compostos (`AND`), escolhas (`OR`) e um tipo por estado
   do ciclo de vida.
4. Ler `references/workflows-and-errors.md` e escrever cada workflow como pipeline de etapas, com
   comando de entrada, eventos de saída, dependências e erros de domínio.
5. Ler `references/boundaries-and-persistence.md` quando houver integração, DTO ou persistência.

**Etapa 6: Traduzir**
1. Detectar a linguagem pelo manifesto do repositório (`go.mod`, `package.json`,
   `pyproject.toml`, `pom.xml`, `build.gradle.kts`, `*.csproj`). Sem repositório, perguntar.
2. Ler `references/translation.md` e traduzir os tipos e as assinaturas dos workflows. Código sem
   comentários e com identificadores em inglês (`R-STYLE-001`).
3. No modo `revisar`, apontar cada violação do piso com `path:linha` e mostrar a versão corrigida.

**Etapa 7: Materializar e validar**
1. Ler `assets/domain-model-template.md` e preencher todas as seções com o contexto real. Seção
   sem conteúdo confirmado diz isso explicitamente.
2. Rodar `python3 "${CLAUDE_SKILL_DIR}/scripts/validate-domain-model.py" <arquivo>` até imprimir
   `SUCCESS`.
3. Se continuar falhando depois de uma correção honesta, encerrar com `blocked` e a saída do
   validador.

**Etapa 8: Relatar**
1. Informar o caminho do arquivo, os tipos e workflows centrais, as invariantes mais sensíveis e os
   itens em aberto.
2. Conferir o resultado contra `references/quality-gates.md` e declarar o gate que não passou.
3. Sugerir `lt:create-technical-specification` quando houver PRD aprovado. Não executar a próxima
   skill.

## Estados finais

- `done`: modelo materializado e validador com `SUCCESS`.
- `needs_input`: falta decisão da pessoa sobre linguagem ubíqua, invariante central, fronteira ou
  erro de domínio do fluxo principal.
- `blocked`: erro de I/O, caminho recusado pelo `lt-sdd.sh` ou validação que continua falhando.

## Tratamento de Erros

- Pedido para modelar como CRUD um fluxo com decisão de negócio: mostrar a regra que o CRUD
  esconde e propor o workflow. Seguir com CRUD só se a pessoa confirmar.
- Código existente que contradiz o modelo: registrar a divergência com `path:linha` em
  `Evidências` e não reescrever o código fora do escopo pedido.
- Linguagem sem construção nativa para escolha exaustiva: usar o padrão de
  `references/translation.md` e declarar a limitação.
- `lt-sdd.sh specs-root` com exit 3 (alvo fora do repositório): parar e reportar, sem gravar em
  outro lugar.

## Atribuição

Os princípios vêm de *Domain Modeling Made Functional*, de Scott Wlaschin (Pragmatic Bookshelf,
2018), resumidos com palavras próprias e sem reprodução de texto do livro. O fluxo de discovery
foi adaptado da skill `domain-modeling-production` de JailtonJunior94/skills.
