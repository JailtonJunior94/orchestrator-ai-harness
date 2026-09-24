# Notação de Tipos

<!-- TL;DR
Notação agnóstica de linguagem para escrever o modelo: tipos simples restritos, AND, OR, estados como tipos, Result, Option e assinaturas de workflow.
Keywords: notação, tipo, and, or, escolha, result, option, restrito, construtor, assinatura
Load complete when: a etapa é escrever ou revisar as seções Tipos do Domínio e Workflows do modelo.
-->

A notação vale para o `domain-model.md`. Ela é lida por quem não programa e traduzida depois
para a linguagem do repositório. Nomes de tipo em PascalCase, na língua do negócio.

## Tipos simples restritos

Envolvem um primitivo e carregam a regra que o torna válido. Só existem por meio do construtor.

```text
type CodigoDoProduto = string   // 7 caracteres, prefixo "W" ou "G"
type Quantidade = inteiro       // entre 1 e 1000
type Email = string             // contém "@" e domínio

criar: string -> Result<CodigoDoProduto, ErroDeValidacao>
```

- Todo tipo restrito declara a regra ao lado e o construtor que devolve `Result`.
- Primitivo sem regra (texto livre de observação) pode continuar primitivo.
- Medidas com unidade viram tipo próprio (`Quilos`, `Reais`), nunca `decimal` solto.

## Composição com AND

Registro em que todos os campos existem juntos.

```text
type EnderecoDeEntrega =
    Logradouro AND Cidade AND Cep

type LinhaDoPedido =
    CodigoDoProduto AND Quantidade AND PrecoUnitario
```

## Escolha com OR

Exatamente um dos casos existe. Cada caso pode carregar dados próprios.

```text
type MeioDeContato =
    | SomenteEmail of Email
    | SomenteEndereco of EnderecoPostal
    | EmailEEndereco of Email AND EnderecoPostal
```

- Escolha substitui combinação de opcionais: no exemplo, "nenhum contato" não é representável.
- Todo consumidor trata todos os casos. Caso novo obriga a revisar os consumidores.

## Opcional

```text
type Cliente =
    Nome AND Email AND Option<Telefone>
```

`Option` só quando a ausência é legítima no negócio. Ausência que depende do estado vira estado.

## Coleção não vazia

```text
type Pedido = ... AND NonEmptyList<LinhaDoPedido>
```

Use quando o negócio proíbe coleção vazia; a regra sai do código de validação e entra no tipo.

## Estados do ciclo de vida

Um tipo por estado, com apenas os campos que o estado possui.

```text
type PedidoNaoValidado = { dados brutos vindos da fronteira }
type PedidoValidado = IdDoPedido AND Cliente AND EnderecoDeEntrega AND NonEmptyList<LinhaValidada>
type PedidoPrecificado = PedidoValidado AND NonEmptyList<LinhaPrecificada> AND ValorTotal

type Pedido =
    | NaoValidado of PedidoNaoValidado
    | Validado of PedidoValidado
    | Precificado of PedidoPrecificado
```

Transição é função de um estado para o próximo, nunca troca de campo `status`.

## Result

```text
Result<Sucesso, Falha>
```

Toda operação que pode falhar por motivo de negócio devolve `Result`. A falha é um tipo de erro
do domínio (ver `workflows-and-errors.md`).

## Assinatura de workflow e de etapa

```text
workflow RealizarPedido =
    ComandoRealizarPedido -> Result<List<EventoRealizarPedido>, ErroRealizarPedido>

etapa ValidarPedido =
    VerificarProdutoExiste         // dependência
    -> VerificarEndereco           // dependência
    -> PedidoNaoValidado           // entrada
    -> Result<PedidoValidado, ErroDeValidacao>
```

- Dependências aparecem antes da entrada e também são assinaturas de função.
- Dependência com I/O declara isso no tipo de retorno (`Async<Result<...>>` ou equivalente).

## Identidade

- Entidade tem identificador próprio (`IdDoPedido`) e é igual a outra pela identidade.
- Value object não tem identificador e é igual a outro pelo valor.
