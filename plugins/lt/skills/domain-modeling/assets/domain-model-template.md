# Modelo de Domínio: [nome do fluxo ou capacidade]

<!-- Status: [draft | done | needs_input | blocked] -->

## Resumo

[Problema de negócio, objetivo e a decisão que o modelo organiza, em até 5 linhas.]

## Escopo

Inclui:
- [item]

Exclui:
- [item]

Requisitos atendidos: [RF-NN, ou "sem PRD"]

## Evidências

Escopo analisado: [paths, módulos ou "greenfield"]

| Achado | Status | Evidência |
|---|---|---|
| [termo, regra ou comportamento] | [confirmado \| suspeito \| ausente \| greenfield] | [path:linha ou motivo] |

## Linguagem Ubíqua

| Termo | Definição | Sinônimos proibidos |
|---|---|---|
| [termo] | [definição] | [termos] |

## Bounded Contexts

| Contexto | Dono | Responsabilidade | Relação com outros contextos |
|---|---|---|---|
| [contexto] | [time] | [responsabilidade] | [padrão e direção] |

## Tipos do Domínio

```text
[tipos restritos, AND, OR e estados do ciclo de vida na notação de type-notation.md]
```

## Workflows

```text
[workflow Nome = Comando -> Result<List<Evento>, Erro>, com as etapas e dependências]
```

Etapas:
1. [etapa]: [entrada] -> [saída], falha com [erro]

## Eventos de Domínio

| Evento | Quando ocorre | Quem consome | Dados publicados |
|---|---|---|---|
| [evento] | [fato] | [consumidor] | [campos] |

## Invariantes e Regras

| Invariante ou regra | Garantida por |
|---|---|
| [regra] | [tipo, etapa do workflow ou restrição de persistência] |

## Erros de Domínio

| Erro | Quando ocorre | Reação esperada |
|---|---|---|
| [erro] | [condição] | [quem reage e como] |

## Fronteiras e Persistência

Entradas externas: [origem, DTO e tradução]

Saídas externas: [eventos publicados, DTO e versão]

Persistência e consistência: [o que é gravado, transação ou consistência eventual, outbox]

Idempotência e concorrência: [chave de idempotência e regra de conflito]

## Tradução para [linguagem]

```text
[tipos e assinaturas de workflow na linguagem do repositório, sem comentários]
```

Limites da linguagem: [o que o compilador não garante e como o repositório compensa]

## Trade-offs e Decisões

| Decisão | Alternativa rejeitada | Motivo |
|---|---|---|
| [decisão] | [alternativa] | [ganho em clareza, robustez ou custo] |

## Itens em Aberto

- [pendência, impacto no modelo e quem decide, ou "Nenhum item em aberto."]
