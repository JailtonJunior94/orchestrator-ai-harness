# Modelo de Domínio: Assinatura do clube de livros

<!-- Status: done -->

## Resumo

Leitores assinam o clube para receber um livro por mês. O modelo organiza o ciclo de vida da
assinatura: criação, ativação pelo primeiro pagamento, pausa limitada e cancelamento.

## Escopo

Inclui:
- Assinar, ativar, pausar, retomar e cancelar.

Exclui:
- Troca de plano e assinatura de presente.

Requisitos atendidos: RF-01, RF-02, RF-03, RF-04

## Evidências

Escopo analisado: greenfield, sem código existente.

| Achado | Status | Evidência |
|---|---|---|
| Ciclo de vida da assinatura | greenfield | Nenhum módulo de assinatura no repositório |
| Gateway de pagamento | confirmado | payments/gateway.go:14 |

## Linguagem Ubíqua

| Termo | Definição | Sinônimos proibidos |
|---|---|---|
| Assinatura | Vínculo mensal entre leitor e plano | Contrato, conta |
| Pausa | Suspensão temporária sem cobrança | Congelamento |

## Bounded Contexts

| Contexto | Dono | Responsabilidade | Relação com outros contextos |
|---|---|---|---|
| Assinaturas | Time Clube | Ciclo de vida da assinatura | Cliente de Pagamentos |

## Tipos do Domínio

```text
type Plano = | Basico | Premium
type MesesDePausa = inteiro   // entre 1 e 2

type AssinaturaPendente = IdDaAssinatura AND IdDoLeitor AND Plano
type AssinaturaAtiva = AssinaturaPendente AND DataDeAtivacao
type AssinaturaPausada = AssinaturaAtiva AND MesesDePausa
type AssinaturaCancelada = IdDaAssinatura AND DataDeCancelamento

type Assinatura =
    | Pendente of AssinaturaPendente
    | Ativa of AssinaturaAtiva
    | Pausada of AssinaturaPausada
    | Cancelada of AssinaturaCancelada
```

## Workflows

```text
workflow Assinar = ComandoAssinar -> Result<List<AssinaturaCriada>, ErroAssinar>
workflow Pausar = ComandoPausar -> Result<List<AssinaturaPausadaEvento>, ErroPausar>
```

Etapas:
1. ValidarPausa: AssinaturaAtiva -> AssinaturaPausada, falha com PausaAcimaDoLimite

## Eventos de Domínio

| Evento | Quando ocorre | Quem consome | Dados publicados |
|---|---|---|---|
| AssinaturaCriada | Leitor assina | Pagamentos | IdDaAssinatura, Plano |

## Invariantes e Regras

| Invariante ou regra | Garantida por |
|---|---|
| Só assinatura ativa pode pausar | Tipo: Pausar recebe AssinaturaAtiva |

## Erros de Domínio

| Erro | Quando ocorre | Reação esperada |
|---|---|---|
| PausaAcimaDoLimite | Pausa pedida acima de 2 meses | Leitor escolhe prazo menor |

## Fronteiras e Persistência

Entradas externas: API do app com DTO próprio, convertido por construtores.

Saídas externas: AssinaturaCriada publicada com DTO versionado.

Persistência e consistência: tabela com coluna de estado e check por estado; outbox para eventos.

Idempotência e concorrência: chave de idempotência no ComandoAssinar; versão otimista.

## Tradução para Go

```go
type Subscription interface {
	isSubscription()
}
```

Limites da linguagem: o compilador não verifica exaustividade do switch de tipo.

## Trade-offs e Decisões

| Decisão | Alternativa rejeitada | Motivo |
|---|---|---|
| Um tipo por estado | Campo status | Impede pausar assinatura pendente |

## Itens em Aberto

- Regra de reembolso no cancelamento não está no PRD; decide o time de produto.
