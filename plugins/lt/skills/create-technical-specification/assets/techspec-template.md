<!-- spec-hash-prd: 0000000000000000000000000000000000000000000000000000000000000000 -->
<!-- MANDATÓRIO: preenchido por `create-technical-specification` Etapa 7.1 com sha256 do PRD consumido.
     Rastreabilidade: `create-tasks` e `execute-task` comparam este hash com o atual do prd.md
     para detectar drift entre techspec e PRD. NÃO remover este comentário ao editar a techspec. -->

# Especificação Técnica

## Resumo Executivo

[Forneça uma visão geral técnica breve da abordagem de solução. Resuma decisões arquiteturais chave e estratégia de implementação em 1-2 parágrafos.]

## Arquitetura do Sistema

### Visão Geral dos Componentes

[Descrição breve dos componentes principais e suas responsabilidades:

- Nomes e funções primárias dos componentes — **listar todo componente novo ou modificado**
- Relacionamentos chave entre componentes
- Visão geral do fluxo de dados]

## Design de Implementação

### Interfaces Chave

[Defina interfaces de serviço principais (máx 20 linhas por exemplo):

```go
// Definição de interface exemplo
type ServiceName interface {
    MethodName(ctx context.Context, input Type) (output Type, error)
}
```

]

### Modelos de Dados

[Defina estruturas de dados essenciais:

- Entidades de domínio centrais (se aplicável)
- Tipos de request/response
- Schemas de banco de dados (se aplicável)]

### Endpoints de API

[Liste endpoints de API se aplicável:

- Método e path (ex.: `POST /api/v0/resource`)
- Descrição breve
- Referências de formato de request/response]

## Pontos de Integração

[Incluir apenas se a funcionalidade requer integrações externas:

- Serviços ou APIs externas
- Requisitos de autenticação
- Abordagem de tratamento de erros]

## Abordagem de Testes

<!-- Regra: R-TEST-002 da constitution. Teste o que importa: cada linha da matriz nomeia o
     comportamento que o teste derruba se quebrar. Sem linha para getter, DTO ou wiring. -->

### Matriz Requisito → Teste

Todo `RF-nn` do PRD tem pelo menos uma linha. RF sem linha é lacuna e reprova no review.

| RF | Nível | Teste (cenário) | Comportamento que derruba se quebrar |
|---|---|---|---|
| RF-01 | unit | [ex: rejeita pedido com total negativo] | [ex: pedido inválido persistido] |
| RF-01 | integração | [ex: grava e relê o pedido no banco real] | [ex: mapeamento de coluna errado] |
| RF-02 | e2e | [ex: cliente conclui a compra] | [ex: jornada de compra quebrada] |

### Testes Unitários

[Domínio, use cases, lógica pura e validadores: caminho feliz, cada falha de negócio e as bordas.
Doubles só nas fronteiras externas.]

### Testes de Integração

[Um por adapter de fronteira que a funcionalidade cria ou altera (banco, fila, cache, cliente HTTP,
filesystem), contra a dependência real efêmera (testcontainers ou equivalente da stack),
separados dos unit tests por tag, marcador ou script. Liste:

- Adapters cobertos e a dependência real de cada um
- Dados de teste e como são criados e removidos]

### Testes E2E

[Só as jornadas críticas de negócio que a funcionalidade cria ou altera: um fluxo por jornada, não
um por requisito. Se nenhuma jornada crítica muda, escreva "nenhuma jornada crítica alterada" e
explique. Para frontend, indique a ferramenta de automação de browser da stack.]

### Cobertura

[Pacotes ou módulos que a funcionalidade toca e a cobertura atual de cada um. Pacote abaixo de 70%
entra no escopo: as tarefas que o tocarem sobem a cobertura até o piso (R-TEST-002.1).]

## Sequenciamento de Desenvolvimento

### Ordem de Build

[Defina sequência de implementação:

1. Primeiro componente ou funcionalidade (por que primeiro)
2. Segundo componente ou funcionalidade (dependências)
3. Componentes subsequentes
4. Integração e testes]

### Dependências Técnicas

[Liste quaisquer dependências bloqueantes:

- Infraestrutura necessária
- Disponibilidade de serviços externos]

## Monitoramento e Observabilidade

[Defina abordagem de monitoramento usando infraestrutura existente:

- Métricas a expor (formato Prometheus)
- Logs chave e níveis de log
- Integração com dashboards Grafana existentes]

## Considerações Técnicas

### Decisões Chave

[Para cada decisão tomada nesta resposta, deve ser criada uma ADR separada seguindo o template `assets/adr-template.md`.]

[Documente decisões técnicas importantes:

- Abordagem escolhida e justificativa
- Trade-offs considerados
- Alternativas rejeitadas e por quê]

### Riscos Conhecidos

[Identifique riscos técnicos:

- Desafios potenciais
- Abordagens de mitigação
- Áreas que precisam de pesquisa]

### Conformidade com Padrões

[Liste regras aplicáveis de `${CLAUDE_PLUGIN_ROOT}/config/` que se aplicam a esta tech spec.]

### Arquivos Relevantes e Dependentes

[Liste arquivos relevantes e dependentes aqui.]
