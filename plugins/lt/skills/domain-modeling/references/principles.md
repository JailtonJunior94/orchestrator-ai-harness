# Princípios de Modelagem

<!-- TL;DR
Decide o que modelar e como reconhecer modelo fraco: comportamento antes de estrutura, estados ilegais irrepresentáveis, economia estrutural.
Keywords: princípio, linguagem ubíqua, estado ilegal, crud, modelo anêmico, economia
Load complete when: a etapa é decidir o escopo do modelo ou avaliar se um modelo existente é fraco.
-->

## 1. Comportamento antes de estrutura

- Começar pelo que acontece: comando, decisão, evento, regra e consequência.
- Não começar por tabela, endpoint, payload, ORM, fila ou classe. Esses artefatos derivam do modelo.
- Pergunta útil para a pessoa: "o que dispara isso, o que precisa ser verdade para seguir e o que
  o negócio quer saber quando termina?".

## 2. O código fala a língua do negócio

- Cada tipo, estado, evento e erro tem o nome que o especialista usa.
- Dentro de um bounded context, um termo tem um significado só. Sinônimo ambíguo vira termo
  proibido na tabela de linguagem ubíqua.
- Termo técnico (`Manager`, `Helper`, `Data`, `Info`, `Processor`) não é linguagem ubíqua.

## 3. Estados ilegais irrepresentáveis

- Se uma combinação de valores não pode existir no negócio, o tipo não deve permitir construí-la.
- Validação espalhada ("o front valida", "o handler confere") não protege invariante: o tipo protege.
- Campo opcional que só existe em certo estado indica que faltam tipos: cada estado vira um tipo
  com exatamente os campos que ele tem.
- Regra que não cabe no tipo (depende de dado externo, de tempo ou de outro agregado) vira
  invariante explícita, verificada numa etapa do workflow e com erro de domínio próprio.

## 4. Validar uma vez, na entrada

- Dado externo entra como tipo não validado e sai da primeira etapa como tipo validado ou erro.
- Depois da validação, o restante do workflow confia no tipo e não revalida.

## 5. Economia estrutural

- Modelar só o que o workflow usa. Campo sem regra e sem consumidor fica de fora.
- Agregado protege o menor conjunto de invariantes que precisa mudar junto na mesma transação.
- Não fragmentar a ponto de cada regra depender de orquestração frágil entre agregados.
- Novo bounded context, evento ou estado exige ganho declarado em `Trade-offs e Decisões`.

## 6. Não inventar semântica

- Regra que a pessoa não confirmou e o código não evidencia não entra como fato.
- Suposição razoável e reversível pode seguir, marcada como suposição.
- Suposição que muda tipo, transição ou erro vira pergunta ou item em aberto.

## Sinais de modelo fraco

- Struct ou classe com muitos campos opcionais e nenhum comportamento.
- Campo `status` em string ou enum livre, com `if status == ...` espalhado.
- `bool` que codifica estado (`isValidated`, `isPaid`) ao lado de campos que só valem num estado.
- Evento que é log de CRUD (`PedidoAtualizado`) sem dizer o que mudou no negócio.
- Tipo de domínio igual ao DTO, com tags de JSON ou ORM.
- Erro genérico (`error`, `Exception`, "operação inválida") onde o negócio reage de formas diferentes.
- Workflow que lê e grava banco entre cada regra, sem núcleo testável sem I/O.
