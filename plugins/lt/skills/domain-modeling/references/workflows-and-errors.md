# Workflows e Erros

<!-- TL;DR
Workflow como pipeline de etapas: comando entra, eventos saem, erros de domínio tipados, dependências explícitas e efeitos nas bordas.
Keywords: workflow, pipeline, comando, evento, result, erro de domínio, dependência, efeito, idempotência
Load complete when: a etapa é desenhar ou revisar workflows, eventos, dependências ou a estratégia de erro.
-->

## Anatomia de um workflow

```text
Comando -> [Validar] -> [Aplicar regra] -> [Decidir] -> [Criar eventos] -> Result<Eventos, Erro>
```

1. **Entrada**: um comando, com os dados que o disparo traz e metadados (quem, quando, correlação).
2. **Etapas**: funções pequenas, cada uma transforma um estado no próximo (`NaoValidado ->
   Validado -> Precificado`).
3. **Saída**: lista de eventos de domínio que descrevem o que aconteceu. O workflow não chama o
   consumidor; quem publica é a borda.
4. **Falha**: um erro de domínio que diz em qual regra o fluxo parou.

## Comando e evento

| | Comando | Evento |
|---|---|---|
| Tempo verbal | Imperativo (`RealizarPedido`) | Passado (`PedidoRealizado`) |
| Pode falhar | Sim | Não; já aconteceu |
| Quem cria | A borda, a partir de UI, API ou mensagem | O workflow |
| Conteúdo | Intenção e dados de entrada | Fato e o que o consumidor precisa para reagir |

Evento que só repete o estado gravado (`PedidoAtualizado`) é log, não evento de domínio. Nomeie o
fato de negócio (`EnderecoDeEntregaAlterado`).

## Dependências explícitas

- Toda dependência entra como parâmetro da etapa, declarada pela assinatura do que ela faz
  (`VerificarProdutoExiste: CodigoDoProduto -> bool`), não pelo componente que a implementa.
- O núcleo não conhece banco, fila, HTTP nem relógio. Instante atual, id gerado e cotação chegam
  como entrada ou como dependência.
- Em linguagem orientada a objetos, a dependência vira interface pequena injetada pelo construtor.

## Efeitos nas bordas

```text
borda de entrada: desserializar, ler estado atual, montar comando
núcleo puro: workflow(comando, estado, dependências) -> Result<Eventos, Erro>
borda de saída: persistir, publicar eventos, responder
```

- Ler tudo que a decisão precisa antes do núcleo; gravar o resultado depois.
- Se a decisão precisa de I/O no meio (consultar estoque, por exemplo), a consulta é uma
  dependência chamada por uma etapa, e o modelo registra o custo e a falha possível dela.

## Três classes de erro

| Classe | Exemplo | Tratamento |
|---|---|---|
| Erro de domínio | Produto inexistente, limite de crédito excedido | Tipo nomeado no `Result`; o negócio decide a reação |
| Erro de infraestrutura | Timeout do banco, fila indisponível | Não vira caso do domínio; a borda trata com retry, circuito ou falha técnica |
| Defeito | Invariante violada que o tipo deveria impedir | Falha rápido e alerta; não é caminho de negócio |

```text
type ErroRealizarPedido =
    | Validacao of ErroDeValidacao
    | Precificacao of ErroDePrecificacao
    | ClienteBloqueado of IdDoCliente
```

- Cada caso existe porque alguém reage a ele de forma diferente. Se todos recebem a mesma
  reação, um caso basta.
- Mensagem para usuário final é tradução na borda, não campo do erro de domínio.

## Encadeamento

- Etapas que devolvem `Result` são encadeadas: a primeira falha interrompe o pipeline e vira a
  saída do workflow.
- Validações independentes (vários campos de um formulário) podem acumular erros em vez de parar
  no primeiro; registre qual estratégia o workflow usa.
- Erros de etapas diferentes são unificados no tipo de erro do workflow.

## Idempotência e concorrência

- Comando que pode chegar duas vezes (retry, mensagem duplicada) carrega chave de idempotência.
- Registre no modelo o que acontece com o segundo comando: mesmo resultado, erro ou nada.
- Conflito entre dois comandos no mesmo agregado precisa de regra explícita (versão otimista,
  fila por agregado ou equivalente); não deixe implícito.
