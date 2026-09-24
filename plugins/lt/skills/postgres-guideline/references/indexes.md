# Índices

<!-- TL;DR
Índice tem custo de escrita, B-tree multicoluna com as colunas de igualdade primeiro, índice parcial e de expressão casando com a query, INCLUDE com parcimônia, GIN para jsonb e arrays, BRIN para dado correlacionado com a ordem física.
Keywords: CREATE INDEX, B-tree, multicolumn, partial, expression, INCLUDE, index-only scan, GIN, BRIN, skip scan
Load complete when: a mudança cria, altera ou remove índice, ou quando a query nova precisa de índice.
-->

- Escopo: escolha e desenho de índice. Para aplicar o índice em tabela com tráfego, ver `migrations.md`.
- Confirme o uso do índice com `EXPLAIN` (ver `queries.md`), nunca pela intuição.

## Sumário

- PG-IDX-001 Todo índice tem custo
- PG-IDX-002 Ordem das colunas no B-tree multicoluna
- PG-IDX-003 Índice parcial
- PG-IDX-004 Índice de expressão
- PG-IDX-005 Índice de cobertura com `INCLUDE`
- PG-IDX-006 Escolha do tipo de índice

## PG-IDX-001 Todo índice tem custo

Doc: o índice precisa ficar sincronizado com a tabela, o que acrescenta custo a toda escrita, e
pode impedir atualização HOT (heap-only tuple). Índice pouco ou nunca usado deve ser removido.

Harness: índice novo aponta a query que ele serve. Antes de remover um índice por falta de uso,
confira `idx_scan` em `pg_stat_user_indexes` em todas as réplicas que recebem leitura, porque cada
servidor tem as próprias estatísticas.

Fonte: https://www.postgresql.org/docs/current/indexes-intro.html,
https://www.postgresql.org/docs/current/monitoring-stats.html

## PG-IDX-002 Ordem das colunas no B-tree multicoluna

Doc: o B-tree multicoluna é mais eficiente com restrição nas colunas iniciais (à esquerda). A regra
exata: igualdade nas colunas iniciais, mais uma desigualdade na primeira coluna sem igualdade,
limitam a parte do índice lida. Índice multicoluna deve ser usado com parcimônia, e mais de três
colunas raramente ajuda. A partir do 18, o skip scan pode aproveitar colunas posteriores mesmo sem
igualdade na coluna inicial, mas só compensa quando a coluna pulada tem poucos valores distintos.

Harness: colunas de igualdade primeiro, depois a de intervalo ou de ordenação. Não conte com skip
scan para justificar a ordem das colunas.

```sql
CREATE INDEX CONCURRENTLY orders_customer_created_idx ON orders (customer_id, created_at);
```

Fonte: https://www.postgresql.org/docs/current/indexes-multicolumn.html

## PG-IDX-003 Índice parcial

Doc: índice parcial evita indexar valores comuns, que a query não usaria via índice de qualquer
forma, e diminui o índice. O predicado da query precisa implicar o predicado do índice para o índice
ser usado. Índice parcial não substitui particionamento.

```sql
CREATE INDEX CONCURRENTLY jobs_pending_idx ON jobs (run_at) WHERE status = 'pending';
```

Fonte: https://www.postgresql.org/docs/current/indexes-partial.html

## PG-IDX-004 Índice de expressão

Doc: o índice pode ser sobre uma expressão, como `lower(email)`. A query só usa o índice quando
escreve a mesma expressão.

```sql
CREATE UNIQUE INDEX CONCURRENTLY users_email_lower_key ON users (lower(email));
SELECT id FROM users WHERE lower(email) = lower($1);
```

Fonte: https://www.postgresql.org/docs/current/indexes-expressional.html

## PG-IDX-005 Índice de cobertura com `INCLUDE`

Doc: um index-only scan evita ler a tabela quando todas as colunas da query estão no índice e as
páginas estão marcadas como visíveis no visibility map. `INCLUDE` acrescenta colunas que não fazem
parte da chave. Seja conservador com colunas de payload, principalmente largas: elas duplicam dado,
incham o índice e a inserção falha se a tupla do índice passar do tamanho máximo.

Fonte: https://www.postgresql.org/docs/current/indexes-index-only-scans.html

## PG-IDX-006 Escolha do tipo de índice

Doc: B-tree é o padrão e serve à maioria dos casos. GIN é um índice invertido, adequado a valores
com vários componentes, como arrays e `jsonb`. BRIN guarda resumos por faixa de blocos e funciona
melhor em colunas correlacionadas com a ordem física das linhas.

Harness: B-tree salvo motivo medido. GIN para busca por conteúdo em `jsonb` ou array. BRIN para
tabela grande só de inserção ordenada por tempo, como log e evento.

Fonte: https://www.postgresql.org/docs/current/indexes-types.html
