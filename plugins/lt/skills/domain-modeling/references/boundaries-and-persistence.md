# Fronteiras e Persistência

<!-- TL;DR
Bounded contexts, mapa de contexto, DTO na fronteira, anticorrupção, serialização, persistência fora do domínio e evolução do modelo sem quebrar consumidores.
Keywords: bounded context, fronteira, dto, acl, serialização, persistência, evento, versão, evolução
Load complete when: o modelo envolve integração entre contextos, contrato externo, persistência ou mudança de um modelo existente.
-->

## Bounded context

- Um bounded context é a fronteira dentro da qual a linguagem ubíqua é consistente e um time é
  dono do modelo.
- O mesmo termo pode existir em dois contextos com significados diferentes (`Pedido` em Vendas e
  em Expedição). Registre a diferença; não unifique à força.
- Contexto se comunica com outro por eventos ou por contrato público, nunca lendo o banco do outro.
- Crie contexto novo só quando houver dono, linguagem ou ritmo de mudança diferentes.

## Mapa de contexto

Para cada relação entre contextos, registre direção e padrão:

| Padrão | Quando usar |
|---|---|
| Parceria | Os dois times evoluem o contrato juntos |
| Cliente e fornecedor | O fornecedor (upstream) atende às necessidades do cliente (downstream) |
| Conformista | O downstream aceita o modelo do upstream sem tradução |
| Camada anticorrupção (ACL) | O modelo do upstream é ruim ou instável; o downstream traduz na entrada |
| Contrato publicado | O upstream publica um formato estável e versionado para vários consumidores |

## DTO na fronteira

```text
entrada: JSON -> DTO -> (validação) -> tipo de domínio
saída:   tipo de domínio -> DTO -> JSON
```

- DTO é estrutura plana de primitivos, feita para serialização. Pode ter campo opcional e string
  livre, porque o dado de fora não é confiável.
- Tipo de domínio não tem tag de JSON, de ORM nem de fila. A tradução fica numa função explícita
  na borda.
- Conversão de DTO para domínio devolve `Result`: é aí que dado externo inválido vira erro.
- Evento publicado para outro contexto também tem DTO próprio; o tipo interno do evento pode
  mudar sem quebrar o consumidor.

## Persistência

- Persistência é borda. O workflow devolve eventos ou o novo estado; a borda grava.
- Escolha (`OR`) em banco relacional: coluna discriminadora com colunas por caso ou tabela por
  caso. Registre a escolha e a regra que impede linha inconsistente (constraint, check).
- Tipo restrito é gravado como primitivo e reconstruído pelo construtor ao ler. Dado lido que não
  passa no construtor é defeito de dados e é tratado como tal, não ignorado.
- Consistência: registre se o agregado exige transação única ou se aceita consistência eventual
  entre agregados, e como falha parcial é compensada.
- Evento e mudança de estado gravados juntos exigem outbox ou mecanismo equivalente; registre qual.

## Evolução do modelo

- Campo novo em evento publicado entra como opcional; remover ou renomear exige nova versão.
- Novo caso numa escolha obriga a revisar todos os consumidores; liste-os.
- Mudança de regra que invalida dados já gravados precisa de estratégia de migração declarada.
- Quando o modelo muda de sentido (um termo passa a significar outra coisa), renomeie o tipo em vez
  de reaproveitar o nome antigo.
