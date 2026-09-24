# Padrões comportamentais

<!-- TL;DR
Chain of Responsibility, Command, Iterator, Mediator, Memento, Observer, State, Strategy, Template Method e Visitor: intenção, sinais fortes, sinais de exclusão, custo, alternativa direta, forma enxuta e o que testar.
Keywords: switch, if por status, transição, algoritmo, política, evento, fila, undo, pipeline, handler, travessia, AST
Load complete when: o candidato ou um vizinho dele distribui comportamento ou comunicação entre objetos.
-->

- Escopo: como responsabilidades e comunicação se distribuem entre objetos.
- Fonte: catálogo do [Refactoring.Guru](https://refactoring.guru/design-patterns/behavioral-patterns); redação própria.

## Sumário

- DP-COM-001 Chain of Responsibility
- DP-COM-002 Command
- DP-COM-003 Iterator
- DP-COM-004 Mediator
- DP-COM-005 Memento
- DP-COM-006 Observer
- DP-COM-007 State
- DP-COM-008 Strategy
- DP-COM-009 Template Method
- DP-COM-010 Visitor

## DP-COM-001 Chain of Responsibility

[Refactoring.Guru](https://refactoring.guru/design-patterns/chain-of-responsibility)

- Intenção: passar uma requisição por uma sequência de handlers, em que cada um trata, enriquece ou encerra.
- Sinais fortes: `sequential_conditional_handlers`; validações ou etapas independentes que mudam de ordem ou de composição.
- Sinais de exclusão: ação que precisa ser enfileirada ou desfeita (Command); notificação para vários interessados (Observer).
- Custo estrutural: médio. Penalizado em `performance_hot_path` com cadeia longa.
- Alternativa direta: lista de funções percorrida em laço, parando no primeiro erro.
- Forma enxuta: middleware `func(next) handler`, ou slice de validadores.
- Testar: cada handler isolado; interrupção no meio da cadeia; ordem da cadeia; requisição que nenhum handler trata.

## DP-COM-002 Command

[Refactoring.Guru](https://refactoring.guru/design-patterns/command)

- Intenção: representar uma ação como dado que pode ser transportado, persistido, reexecutado ou desfeito.
- Sinais fortes: `request_as_data`; fila, retry, agendamento, auditoria ou `undo_or_replay`.
- Sinais de exclusão: callback simples sem ciclo de vida; pipeline de handlers.
- Custo estrutural: médio.
- Alternativa direta: chamada direta de função, quando nada precisa sobreviver ao momento da chamada.
- Forma enxuta: payload imutável e serializável mais um handler determinístico e idempotente.
- Testar: serializar e desserializar sem perda; reexecução idempotente; undo restaura o estado anterior.

## DP-COM-003 Iterator

[Refactoring.Guru](https://refactoring.guru/design-patterns/iterator)

- Intenção: percorrer uma coleção sem expor a representação interna.
- Sinais fortes: `custom_traversal`; estrutura interna não trivial ou mais de uma ordem de travessia.
- Sinais de exclusão: laço simples sobre lista pública; a linguagem já oferece iteração (`range`, `for...of`, generator).
- Custo estrutural: baixo a médio.
- Alternativa direta: expor uma cópia da coleção ou um método que recebe um callback.
- Forma enxuta: generator, iterador nativo da linguagem (`iter.Seq` em Go 1.23 ou superior, `Symbol.iterator` em JavaScript).
- Testar: coleção vazia; ordem da travessia; parada antecipada; alteração durante a travessia.

## DP-COM-004 Mediator

[Refactoring.Guru](https://refactoring.guru/design-patterns/mediator)

- Intenção: centralizar a coordenação entre componentes que se chamam demais.
- Sinais fortes: `dense_colleague_coordination`; mudar um componente obriga a mudar vários outros.
- Sinais de exclusão: fluxo linear; notificação simples; barramento de eventos já existente e suficiente.
- Custo estrutural: alto. Barra alta (DP-GATE-005).
- Alternativa direta: um serviço orquestrador que chama os componentes em ordem.
- Forma enxuta: coordenador único que conhece os componentes; os componentes só conhecem o coordenador.
- Testar: cada regra de coordenação; componentes testáveis sem os outros; o coordenador não vira objeto que faz tudo.

## DP-COM-005 Memento

[Refactoring.Guru](https://refactoring.guru/design-patterns/memento)

- Intenção: salvar e restaurar o estado de um objeto sem expor os detalhes internos.
- Sinais fortes: `snapshot_and_restore`; undo e redo; checkpoint e rollback local.
- Sinais de exclusão: log de eventos já permite reconstruir; cópia simples basta; estado grande demais para snapshot.
- Custo estrutural: médio. Penalizado com `tight_memory_budget`.
- Alternativa direta: guardar o valor imutável anterior.
- Forma enxuta: snapshot imutável e opaco devolvido pelo próprio objeto, com `restore(snapshot)`.
- Testar: restaurar devolve exatamente o estado salvo; snapshot não muda quando o objeto muda; limite de histórico.

## DP-COM-006 Observer

[Refactoring.Guru](https://refactoring.guru/design-patterns/observer)

- Intenção: avisar vários interessados sobre um evento sem que o emissor os conheça.
- Sinais fortes: `event_fanout`; `must_support_broadcast`; o número de interessados muda.
- Sinais de exclusão: ordem estrita entre receptores; coordenação central (Mediator); um único interessado fixo.
- Custo estrutural: médio. O fluxo fica menos visível; a falha de um assinante precisa de política explícita.
- Alternativa direta: chamada direta, quando o interessado é um só e estável.
- Forma enxuta: lista de callbacks com cancelamento de inscrição; evento de domínio publicado num barramento que o projeto já usa.
- Testar: todos os assinantes recebem; cancelar inscrição para de receber; falha de um assinante não derruba os outros; sem vazamento de assinante.

## DP-COM-007 State

[Refactoring.Guru](https://refactoring.guru/design-patterns/state)

- Intenção: mudar o comportamento de um objeto conforme o estado interno, com transições explícitas.
- Sinais fortes: `state_transition_driven_behavior`; o mesmo `if status == ...` repetido em várias operações; transições válidas e inválidas.
- Sinais de exclusão: só algoritmos intercambiáveis (Strategy); dois estados sem regras próprias; enum simples basta.
- Custo estrutural: médio.
- Alternativa direta: tabela de transições (`estado atual + evento -> próximo estado`) num único lugar.
- Forma enxuta: um tipo por estado implementando as operações, ou tabela de transições com funções por estado.
- Testar: cada transição válida; cada transição inválida rejeitada com erro; operação permitida e proibida por estado.

## DP-COM-008 Strategy

[Refactoring.Guru](https://refactoring.guru/design-patterns/strategy)

- Intenção: trocar algoritmos ou políticas equivalentes atrás do mesmo contrato.
- Sinais fortes: `runtime_algorithm_swap`; `switch` por tipo que cresce a cada variante nova; `must_support_runtime_switch`.
- Sinais de exclusão: comportamento governado por transição de estado (State); uma única variante.
- Custo estrutural: baixo a médio.
- Alternativa direta: mapa `chave -> função`, que é a forma mais barata de Strategy.
- Forma enxuta: interface de um método ou tipo função, escolhida por mapa; chave desconhecida falha de forma explícita.
- Testar: cada estratégia isolada; seleção pela chave; chave desconhecida; contrato comum respeitado por todas.

## DP-COM-009 Template Method

[Refactoring.Guru](https://refactoring.guru/design-patterns/template-method)

- Intenção: fixar o esqueleto de um algoritmo e deixar etapas específicas variarem.
- Sinais fortes: `fixed_workflow_with_variable_steps`; `inheritance_already_natural`; a mesma ordem de passos duplicada em várias classes.
- Sinais de exclusão: `avoid_inheritance`; troca em tempo de execução; linguagem sem herança de implementação (Go).
- Custo estrutural: médio. Herança frágil.
- Alternativa direta: função que recebe as etapas variáveis como parâmetros (Strategy por etapa).
- Forma enxuta: função de fluxo fixo que recebe uma interface pequena com as etapas.
- Testar: ordem dos passos preservada; cada variação de etapa; falha numa etapa interrompe o fluxo.

## DP-COM-010 Visitor

[Refactoring.Guru](https://refactoring.guru/design-patterns/visitor)

- Intenção: somar operações novas a uma hierarquia estável sem alterar os tipos visitados.
- Sinais fortes: `stable_structure_many_operations`; AST ou modelo com tipos fixos e operações novas frequentes.
- Sinais de exclusão: a estrutura muda com frequência; uma ou duas operações; um método no próprio tipo basta.
- Custo estrutural: alto. Barra alta (DP-GATE-005).
- Alternativa direta: `switch` exaustivo sobre o tipo, com verificação do compilador quando a linguagem oferece (union discriminada, sealed, pattern matching).
- Forma enxuta: interface com um método por tipo visitado e `accept` em cada tipo.
- Testar: cada tipo visitado por cada operação; tipo novo quebra a compilação ou um teste de exaustividade.
