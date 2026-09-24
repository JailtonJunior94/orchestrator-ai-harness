# Queries e desempenho

<!-- TL;DR
Medir com EXPLAIN (ANALYZE, BUFFERS) em volume realista e DML dentro de BEGIN/ROLLBACK, estatísticas em dia, paginação sem OFFSET grande e com ORDER BY, NOT IN com NULL, materialização de CTE, carga em lote com COPY.
Keywords: EXPLAIN, ANALYZE, BUFFERS, Seq Scan, rows, LIMIT, OFFSET, ORDER BY, NOT IN, NOT EXISTS, WITH, MATERIALIZED, COPY
Load complete when: a mudança cria ou altera query, investiga lentidão ou faz carga em lote.
-->

- Escopo: SQL de leitura e escrita escrito pela aplicação ou pela migração.
- Para escolher o índice que o plano pede, ver `indexes.md`.

## Sumário

- PG-QRY-001 Medir com `EXPLAIN (ANALYZE, BUFFERS)`
- PG-QRY-002 `EXPLAIN ANALYZE` executa a query
- PG-QRY-003 Estatísticas em dia
- PG-QRY-004 Paginação
- PG-QRY-005 `NOT IN` com NULL
- PG-QRY-006 Materialização de CTE
- PG-QRY-007 Carga em lote

## PG-QRY-001 Medir com `EXPLAIN (ANALYZE, BUFFERS)`

Doc: `ANALYZE` executa a query e mostra tempo real e linhas reais por nó. `BUFFERS` mostra blocos
lidos do cache (`hit`) e do disco (`read`). A partir do 18, `BUFFERS` entra automaticamente com
`ANALYZE`. O resultado não se extrapola para situações muito diferentes da testada: plano medido em
tabela de brinquedo não vale para tabela grande, porque o custo estimado não é linear.

Harness: query nova ou alterada em caminho quente vem com o plano medido em volume próximo do de
produção. Na leitura do plano, procure primeiro:

1. Diferença grande entre `rows` estimado e real: estatística velha ou correlação que o planner não vê.
2. `Seq Scan` com filtro que descarta quase tudo em tabela grande: falta índice ou o predicado não o usa.
3. `Rows Removed by Filter` alto depois de um index scan: índice pouco seletivo para esse predicado.
4. `read` muito maior que `hit`: a query depende de disco.

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, total FROM orders WHERE customer_id = $1 ORDER BY created_at DESC LIMIT 20;
```

Fonte: https://www.postgresql.org/docs/current/using-explain.html,
https://www.postgresql.org/docs/current/sql-explain.html

## PG-QRY-002 `EXPLAIN ANALYZE` executa a query

Doc: com `ANALYZE`, a query roda de fato. A saída de um `SELECT` é descartada, mas qualquer efeito
colateral acontece. Para medir `INSERT`, `UPDATE`, `DELETE` ou `MERGE` sem alterar dado, rode dentro
de uma transação e desfaça.

```sql
BEGIN;
EXPLAIN (ANALYZE, BUFFERS) UPDATE orders SET status = 'paid' WHERE id = $1;
ROLLBACK;
```

Harness: nunca rode `EXPLAIN ANALYZE` de DML em produção, nem com `ROLLBACK`: a execução pega os
mesmos locks.

Fonte: https://www.postgresql.org/docs/current/sql-explain.html

## PG-QRY-003 Estatísticas em dia

Doc: depois de mudar bastante a distribuição dos dados de uma tabela, inclusive por carga em lote,
rodar `ANALYZE` é fortemente recomendado para o planner ter estatística atualizada.

Harness: migração que faz backfill ou carga grande termina com `ANALYZE tabela;`.

Fonte: https://www.postgresql.org/docs/current/populate.html#POPULATE-ANALYZE,
https://www.postgresql.org/docs/current/planner-stats.html

## PG-QRY-004 Paginação

Doc: sem `ORDER BY` que defina uma ordem única, páginas diferentes com `LIMIT` e `OFFSET` podem
devolver resultado inconsistente. As linhas puladas por `OFFSET` são computadas no servidor, então
`OFFSET` grande é ineficiente.

Harness: toda paginação tem `ORDER BY` que termina numa coluna única. Lista que pode crescer usa
paginação por chave (a página seguinte começa depois da última chave vista), apoiada num índice com
as mesmas colunas do `ORDER BY`:

```sql
SELECT id, created_at, total
FROM orders
WHERE customer_id = $1
  AND (created_at, id) < ($2, $3)
ORDER BY created_at DESC, id DESC
LIMIT 20;
```

Prática: o nome "paginação por chave" (keyset) não aparece na documentação. A comparação de
row constructor usada acima está documentada em
https://www.postgresql.org/docs/current/functions-comparisons.html.

Fonte: https://www.postgresql.org/docs/current/queries-limit.html

## PG-QRY-005 `NOT IN` com NULL

Doc: se a subquery de `NOT IN` devolve algum NULL e nenhum valor igual, o resultado é NULL, não
verdadeiro. A linha some do resultado sem erro.

Harness: exclusão por subquery usa `NOT EXISTS`, que não tem essa armadilha.

```sql
SELECT c.id FROM customers c
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.customer_id = c.id);
```

Fonte: https://www.postgresql.org/docs/current/functions-subquery.html

## PG-QRY-006 Materialização de CTE

Doc: CTE não recursiva e sem efeito colateral é incorporada à query principal quando é referenciada
uma vez só. Referenciada mais de uma vez, é materializada. `MATERIALIZED` e `NOT MATERIALIZED`
forçam a escolha.

Harness: só force a escolha com plano medido que mostre o ganho.

Fonte: https://www.postgresql.org/docs/current/queries-with.html

## PG-QRY-007 Carga em lote

Doc: `COPY` carrega muitas linhas com muito menos custo que uma série de `INSERT`. Em carga grande,
remover e recriar índices e FKs e rodar `ANALYZE` no fim também ajudam.

Harness: remover índice ou FK de tabela com tráfego não é opção. Nesse caso, carga em lotes
limitados, cada um na própria transação (ver `migrations.md`, PG-MIG-007).

Fonte: https://www.postgresql.org/docs/current/populate.html
