# Seleção de padrão

<!-- TL;DR
Converte evidência em sinais canônicos, liga cada sinal aos padrões candidatos, desempata pares que se confundem e define quando recusar ou pedir mais evidência.
Keywords: sinal, candidato, desempate, Strategy, State, Decorator, Proxy, Adapter, Facade, Factory, Builder, recusa, ambíguo
Load complete when: a decisão precisa escolher entre padrões ou decidir se algum se aplica.
-->

- Escopo: da evidência coletada até um candidato primário, ou até a recusa.
- Fonte: matriz de seleção da skill design-patterns-mandatory, reescrita para este harness.

## Sumário

- DP-SEL-001 Sinais estruturais
- DP-SEL-002 Sinais e restrições de contexto
- DP-SEL-003 Regras de desempate
- DP-SEL-004 Recusa e evidência insuficiente

## DP-SEL-001 Sinais estruturais

Cada sinal só entra na decisão se apontar para uma linha de código, um contrato ou uma restrição
declarada. Semelhança de nome ou de domínio não é sinal.

| Sinal | O que a evidência mostra | Candidatos |
|---|---|---|
| `single_product_variation` | Um ponto de criação escolhe entre variantes de um único tipo de produto | Factory Method |
| `family_of_related_products` | Vários produtos precisam trocar juntos para continuar compatíveis | Abstract Factory |
| `stepwise_construction` | Objeto com muitos campos opcionais, validação entre campos ou ordem de montagem | Builder |
| `clone_template` | Criação cara ou configuração base reaproveitada com pequenas variações | Prototype |
| `single_process_shared_resource` | Recurso que só pode existir uma vez por processo, com inicialização coordenada | Singleton |
| `external_interface_mismatch` | Contrato de biblioteca, legado ou API externa diferente do que o cliente espera | Adapter |
| `dual_axis_variation` | Duas dimensões variam de forma independente e a combinação explode em subclasses | Bridge |
| `recursive_tree_structure` | Estrutura parte e todo real, com operações recursivas | Composite |
| `uniform_component_contract` | Folhas e agregados respondem à mesma interface | Composite |
| `add_responsibilities_dynamically` | Comportamentos opcionais combinados em tempo de execução pela mesma interface | Decorator |
| `subsystem_too_complex` | Cliente precisa orquestrar muitos passos ou APIs ruidosas de um subsistema | Facade |
| `high_memory_duplication` | Muitos objetos equivalentes repetem o mesmo estado, com pressão de memória medida | Flyweight |
| `access_control_or_lazy_loading` | Acesso precisa de cache, carga tardia, autorização, limite de taxa ou fronteira remota | Proxy |
| `sequential_conditional_handlers` | Requisição passa por etapas independentes que podem tratar, enriquecer ou encerrar | Chain of Responsibility |
| `request_as_data` | Ação precisa ser enfileirada, persistida, reexecutada, auditada ou desfeita | Command |
| `custom_traversal` | Estrutura interna não trivial ou mais de uma forma de percorrer | Iterator |
| `dense_colleague_coordination` | Muitos componentes trocam chamadas cruzadas que uma coordenação central cortaria | Mediator |
| `snapshot_and_restore` | Estado precisa ser salvo e restaurado sem expor a representação interna | Memento |
| `event_fanout` | Um emissor notifica um número variável de interessados | Observer |
| `state_transition_driven_behavior` | Comportamento muda por status, com transições válidas e regras por estado | State |
| `runtime_algorithm_swap` | Algoritmos ou políticas equivalentes escolhidos em tempo de execução | Strategy |
| `fixed_workflow_with_variable_steps` | Ordem do algoritmo é fixa e só algumas etapas variam | Template Method |
| `stable_structure_many_operations` | Hierarquia de tipos estável e operações novas surgindo com frequência | Visitor |

## DP-SEL-002 Sinais e restrições de contexto

Estes sinais não escolhem padrão: eles pesam contra ou a favor de um candidato.

| Sinal ou restrição | Efeito |
|---|---|
| `prefer_direct_solution`, `single_variant_only`, `low_change_frequency` | Pesam para `não aplicar padrão`. |
| `performance_hot_path`, `tight_latency_budget` | Penalizam indireção extra (Decorator empilhado, Chain longa, Visitor). |
| `memory_pressure`, `tight_memory_budget` | Habilitam Flyweight; penalizam Memento de estado grande. |
| `strict_test_isolation`, `avoid_global_state`, `multi_tenant_context` | Reprovam Singleton. |
| `avoid_inheritance`, `prefer_composition` | Reprovam Template Method; favorecem Strategy. |
| `inheritance_already_natural` | Mantém Template Method como opção. |
| `remote_boundary`, `must_support_remote_access` | Favorecem Proxy. |
| `undo_or_replay`, `must_support_undo` | Favorecem Command, com Memento como complementar. |
| `must_support_broadcast` | Favorece Observer. |
| `must_support_checkpoints` | Favorece Memento. |
| `must_support_runtime_switch` | Favorece Strategy sobre Template Method. |
| `cross_product_consistency` | Condição para Abstract Factory. |
| `preserve_public_contract` | Favorece Adapter, Proxy e Decorator, que mantêm a interface. |
| `minimize_class_count`, `minimize_indirection`, `team_needs_low_cognitive_load` | Favorecem a forma funcional do padrão ou a recusa. |

## DP-SEL-003 Regras de desempate

| Par | Escolha o primeiro quando | Escolha o segundo quando | Sem separação |
|---|---|---|---|
| Strategy × State | Algoritmos trocam sem transição governada | Há estados válidos, transições e regras por estado | Evidência insuficiente |
| Decorator × Proxy | O ganho vem de empilhar responsabilidades opcionais | O ganho vem de governar acesso, carga tardia, cache ou fronteira remota | Wrapper que só controla acesso é Proxy |
| Factory Method × Abstract Factory | Só um produto varia | Uma família inteira troca junta | Sem família consistente, recusar Abstract Factory |
| Strategy × Template Method | Variação por composição ou em tempo de execução | Ordem fixa e herança aceitável | `avoid_inheritance` decide por Strategy |
| Bridge × Strategy | Duas dimensões variam de forma combinatória | Só a política varia dentro de um contexto | Uma dimensão só: recusar Bridge |
| Adapter × Facade | O problema é contrato incompatível | O problema é excesso de passos | Facade pode usar Adapter por dentro; primário é o problema central |
| Adapter × Proxy | O ganho é traduzir contrato | O ganho é governar acesso | Evidência insuficiente |
| Facade × Proxy | O ganho é simplificar um subsistema | O ganho é proteger ou controlar um recurso | Evidência insuficiente |
| Command × Chain of Responsibility | A ação é transportada, persistida, reexecutada ou desfeita | A requisição passa por handlers em sequência | Sem fila, undo ou replay, não é Command |
| Observer × Mediator | Emissor avisa assinantes sem conhecê-los | Colegas precisam de regras centrais de orquestração | Ordem crítica entre receptores enfraquece Observer |
| Composite × Visitor | O problema é representar e operar a árvore | A árvore já existe, é estável e ganha operações novas | Visitor não substitui Composite |
| Composite × Decorator | Foco em parte e todo | Foco em somar responsabilidade a um componente | Sem árvore, recusar Composite |
| Iterator × Visitor | O problema é percorrer | O problema é somar operações sobre tipos estáveis | Percorrer árvore não justifica Visitor |
| Flyweight × Singleton | Cardinalidade alta e memória | Unicidade controlada de recurso | Instância única compartilhada não é Flyweight |
| Builder × Abstract Factory | Montar um objeto complexo | Produzir famílias coerentes | Um objeto só: recusar Abstract Factory |
| Memento × Prototype | Salvar e restaurar estado | Clonar ponto de partida configurado | Sem restauração futura, Memento está errado |

## DP-SEL-004 Recusa e evidência insuficiente

- Só sinais de contexto a favor da solução direta (`prefer_direct_solution`, `single_variant_only`,
  `low_change_frequency`), sem sinal estrutural forte: `Recomendar: não aplicar padrão`.
- Nenhum sinal estrutural confirmado por evidência: `Evidência insuficiente`, pedindo o trecho de
  código ou o número de variantes que existe hoje.
- Padrão dependente de herança com `avoid_inheritance` presente e sem contrapeso forte: penalizar
  até reprovar.
- Composite sem `uniform_component_contract` provado: recusar ou pedir evidência, nunca presumir o
  contrato comum.
- Dois candidatos que o desempate não separa: `Evidência insuficiente`, com a pergunta que separa.
