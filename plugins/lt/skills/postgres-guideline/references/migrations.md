# Migração sem downtime

<!-- TL;DR
ALTER TABLE pega ACCESS EXCLUSIVE salvo exceção documentada, lock_timeout antes de DDL, índice com CONCURRENTLY fora de transação e checagem de INVALID, constraint com NOT VALID e VALIDATE, SET NOT NULL apoiado em CHECK validado, ADD COLUMN com default não volátil, mudança de tipo reescreve, expand/contract e backfill em lotes.
Keywords: ALTER TABLE, ACCESS EXCLUSIVE, SHARE UPDATE EXCLUSIVE, lock_timeout, CREATE INDEX CONCURRENTLY, DROP INDEX CONCURRENTLY, REINDEX CONCURRENTLY, INVALID, NOT VALID, VALIDATE CONSTRAINT, SET NOT NULL, ADD COLUMN, DEFAULT, SET DATA TYPE, backfill
Load complete when: a mudança adiciona ou altera arquivo de migração, ou roda DDL em tabela que recebe tráfego.
-->

- Escopo: DDL aplicado em banco que está atendendo tráfego.
- Toda regra aqui pressupõe tabela com tráfego. Tabela criada na mesma migração não precisa delas.

## Sumário

- PG-MIG-001 Saber o lock de cada comando
- PG-MIG-002 `lock_timeout` antes de DDL
- PG-MIG-003 Índice com `CONCURRENTLY`
- PG-MIG-004 Constraint com `NOT VALID` e `VALIDATE`
- PG-MIG-005 `SET NOT NULL` sem varrer a tabela com lock exclusivo
- PG-MIG-006 Coluna nova e mudança de tipo
- PG-MIG-007 Expand/contract e backfill em lotes
- PG-MIG-008 Unique e primary key a partir de índice pronto

## PG-MIG-001 Saber o lock de cada comando

Doc: `ALTER TABLE` pega `ACCESS EXCLUSIVE` salvo quando a documentação do subcomando diz outra coisa.
Com vários subcomandos, vale o lock mais forte entre eles. `ACCESS EXCLUSIVE` conflita com todos os
modos, inclusive o `ACCESS SHARE` de um `SELECT`. Exceções relevantes:

| Comando | Lock na tabela alterada |
|---|---|
| `ADD FOREIGN KEY` | `SHARE ROW EXCLUSIVE` (também na tabela referenciada) |
| `VALIDATE CONSTRAINT` | `SHARE UPDATE EXCLUSIVE` (mais `ROW SHARE` na referenciada, se FK) |
| `SET STATISTICS`, `SET (fillfactor, autovacuum_*)` | `SHARE UPDATE EXCLUSIVE` |
| `CREATE INDEX` sem `CONCURRENTLY` | bloqueia escrita, não leitura |
| `CREATE INDEX CONCURRENTLY` | não bloqueia `INSERT`, `UPDATE` nem `DELETE` |

Harness: a revisão de toda migração anota, para cada comando, o lock e se ele reescreve a tabela.

Fonte: https://www.postgresql.org/docs/current/sql-altertable.html,
https://www.postgresql.org/docs/current/explicit-locking.html

## PG-MIG-002 `lock_timeout` antes de DDL

Doc: `lock_timeout` aborta o comando que esperar mais que o limite para pegar um lock, e o limite
vale para cada tentativa de lock. Não é recomendado definir no `postgresql.conf`, porque afeta todas
as sessões.

Prática: um `ALTER TABLE` esperando `ACCESS EXCLUSIVE` atrás de uma transação longa fica na fila e
os comandos que chegam depois esperam atrás dele. Sem `lock_timeout`, uma migração parada vira
indisponibilidade. Com ele, a migração falha rápido e pode ser repetida.

Harness: toda migração que altera tabela com tráfego define `lock_timeout` curto na própria
transação, e a execução aceita ser repetida.

```sql
SET LOCAL lock_timeout = '5s';
ALTER TABLE orders ADD COLUMN source text;
```

Fonte: https://www.postgresql.org/docs/current/runtime-config-client.html#GUC-LOCK-TIMEOUT

## PG-MIG-003 Índice com `CONCURRENTLY`

Doc: `CREATE INDEX` comum bloqueia escrita na tabela até terminar. Com `CONCURRENTLY`, a escrita
continua, ao custo de duas varreduras da tabela e de esperar as transações existentes terminarem.
`CREATE INDEX CONCURRENTLY` não roda dentro de bloco de transação e só um build concorrente por
tabela roda por vez. Se falhar (deadlock, violação de unicidade), deixa um índice `INVALID` que a
query ignora mas que continua custando na escrita, e um único inválido continua impondo a
unicidade. A recuperação recomendada é remover o índice e tentar de novo, ou usar
`REINDEX INDEX CONCURRENTLY`. Em tabela particionada, crie o índice concorrente em cada partição e
depois o índice na tabela pai, que vira operação só de metadado. `DROP INDEX CONCURRENTLY` e
`REINDEX ... CONCURRENTLY` existem com restrições parecidas.

Harness: a migração de índice concorrente fica num arquivo próprio, marcado como não transacional
na ferramenta de migração do repo, e usa `IF NOT EXISTS` só junto com a checagem de validade:

```sql
CREATE INDEX CONCURRENTLY IF NOT EXISTS orders_customer_id_idx ON orders (customer_id);
SELECT indexrelid::regclass FROM pg_index WHERE NOT indisvalid;
```

`IF NOT EXISTS` sozinho engana. A documentação avisa que não há garantia de que o índice existente
se pareça com o que seria criado, então um índice `INVALID` de uma tentativa anterior faz o comando
passar sem construir nada.

Fonte: https://www.postgresql.org/docs/current/sql-createindex.html#SQL-CREATEINDEX-CONCURRENTLY,
https://www.postgresql.org/docs/current/sql-dropindex.html,
https://www.postgresql.org/docs/current/sql-reindex.html

## PG-MIG-004 Constraint com `NOT VALID` e `VALIDATE`

Doc: adicionar FK, `CHECK` ou `NOT NULL` varre a tabela, e as escritas ficam bloqueadas até o
commit. Com `NOT VALID`, a varredura é pulada e o commit é imediato, mas a constraint já vale para
linhas novas e alteradas. Depois, `VALIDATE CONSTRAINT` confere as linhas antigas pegando só
`SHARE UPDATE EXCLUSIVE`, que não bloqueia escrita. `NOT VALID` vale para FK e `CHECK` e, a partir
do 18, para `NOT NULL`.

Harness: em tabela grande, as duas etapas ficam em transações separadas.

```sql
ALTER TABLE order_items
    ADD CONSTRAINT order_items_order_id_fkey
    FOREIGN KEY (order_id) REFERENCES orders (id) NOT VALID;

ALTER TABLE order_items VALIDATE CONSTRAINT order_items_order_id_fkey;
```

Fonte: https://www.postgresql.org/docs/current/sql-altertable.html#SQL-ALTERTABLE-NOTES

## PG-MIG-005 `SET NOT NULL` sem varrer a tabela com lock exclusivo

Doc: `SET NOT NULL` varre a tabela inteira, salvo quando existe um `CHECK` válido que prova que não
há NULL: aí a varredura é pulada. `SET NOT NULL` usa o lock padrão do `ALTER TABLE`,
`ACCESS EXCLUSIVE`.

Harness: em tabela grande, abaixo do 18:

```sql
ALTER TABLE orders ADD CONSTRAINT orders_source_not_null CHECK (source IS NOT NULL) NOT VALID;
ALTER TABLE orders VALIDATE CONSTRAINT orders_source_not_null;
ALTER TABLE orders ALTER COLUMN source SET NOT NULL;
ALTER TABLE orders DROP CONSTRAINT orders_source_not_null;
```

No 18 ou superior, a alternativa é `ADD CONSTRAINT ... NOT NULL source NOT VALID` seguida de
`VALIDATE CONSTRAINT`.

Fonte: https://www.postgresql.org/docs/current/sql-altertable.html#SQL-ALTERTABLE-DESC-SET-DROP-NOT-NULL

## PG-MIG-006 Coluna nova e mudança de tipo

Doc: `ADD COLUMN` com `DEFAULT` não volátil guarda o valor no catálogo e não reescreve a tabela, o
que é rápido mesmo em tabela grande. `DEFAULT` volátil (como `clock_timestamp()`), coluna gerada
armazenada, coluna identity ou domínio com constraint reescrevem a tabela e os índices. Mudar o tipo
de uma coluna normalmente reescreve tudo. A exceção é quando o `USING` não muda o conteúdo e o tipo
antigo é binário-compatível com o novo, mas os índices afetados ainda podem ser reconstruídos. A
reescrita não é segura para MVCC: transações concorrentes com snapshot anterior veem a tabela vazia.

Harness: mudança que reescreve tabela grande com tráfego vira expand/contract (PG-MIG-007).

Fonte: https://www.postgresql.org/docs/current/sql-altertable.html#SQL-ALTERTABLE-NOTES

## PG-MIG-007 Expand/contract e backfill em lotes

Prática: a documentação não descreve este padrão. Para renomear, mudar tipo ou dividir coluna sem
parar a aplicação:

1. Expand: criar a estrutura nova sem remover a antiga. A aplicação passa a escrever nas duas.
2. Backfill em lotes pequenos, cada lote na própria transação, com pausa entre eles e `ANALYZE` no fim.
3. A aplicação passa a ler da estrutura nova.
4. Contract: remover a estrutura antiga numa versão posterior, depois que nenhuma instância em
   execução a usa.

```sql
UPDATE orders
SET amount_cents = (amount * 100)::bigint
WHERE id IN (
    SELECT id FROM orders
    WHERE amount_cents IS NULL
    ORDER BY id
    LIMIT 5000
);
```

Harness: remoção de coluna, tabela ou constraint usada pela versão em produção nunca vai no mesmo
deploy que a mudança de código que para de usá-la.

## PG-MIG-008 Unique e primary key a partir de índice pronto

Doc: `ADD CONSTRAINT ... UNIQUE USING INDEX` ou `PRIMARY KEY USING INDEX` transforma um índice único
existente em constraint. O índice não pode ser parcial nem ter expressão e precisa ser B-tree com a
ordenação padrão.

Harness: crie o índice com `CREATE UNIQUE INDEX CONCURRENTLY` e depois anexe a constraint, em vez de
`ADD CONSTRAINT ... UNIQUE` direto, que constrói o índice com lock exclusivo.

Fonte: https://www.postgresql.org/docs/current/sql-altertable.html
