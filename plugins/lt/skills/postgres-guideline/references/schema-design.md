# Modelagem de schema

<!-- TL;DR
Escolha de tipo (timestamptz, numeric, text, identity, jsonb, uuid), NOT NULL como padrão, unicidade com NULL, FK com índice nas colunas de referência.
Keywords: CREATE TABLE, timestamptz, numeric, money, serial, identity, varchar, text, jsonb, uuid, NOT NULL, UNIQUE, FOREIGN KEY, CHECK
Load complete when: a mudança cria tabela, adiciona ou altera coluna, escolhe tipo ou declara constraint.
-->

- Escopo: `CREATE TABLE`, `ADD COLUMN` e escolha de tipo ou constraint.
- Para o impacto de lock ao aplicar a mudança numa tabela existente, ver `migrations.md`.

## Sumário

- PG-SCH-001 Instante no tempo é `timestamptz`
- PG-SCH-002 Valor exato é `numeric`
- PG-SCH-003 Chave gerada com identity
- PG-SCH-004 Texto sem limite arbitrário
- PG-SCH-005 `jsonb` no lugar de `json`
- PG-SCH-006 `uuid` como tipo nativo
- PG-SCH-007 `NOT NULL` como padrão
- PG-SCH-008 Unicidade e NULL
- PG-SCH-009 FK com índice nas colunas de referência

## PG-SCH-001 Instante no tempo é `timestamptz`

Doc: um `timestamp with time zone` é convertido para UTC na entrada e exibido no fuso da sessão
(`TimeZone`) na saída. `timestamp` sem fuso não faz essa conversão. A documentação não recomenda
`time with time zone`.

Harness: todo instante (criação, evento, expiração) usa `timestamptz`. `timestamp` sem fuso só para
horário de parede sem fuso associado (por exemplo, "abre às 09:00 em qualquer loja"). Nunca
`time with time zone`.

```sql
CREATE TABLE orders (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    created_at timestamptz NOT NULL DEFAULT now()
);
```

Fonte: https://www.postgresql.org/docs/current/datatype-datetime.html

## PG-SCH-002 Valor exato é `numeric`

Doc: `real` e `double precision` são inexatos. Para armazenamento e cálculo exatos, como valores
monetários, use `numeric`. A saída de `money` depende de `lc_monetary`, o que pode quebrar a carga
de um dump em banco com outra configuração.

Harness: dinheiro é `numeric(p, s)` com escala explícita, ou inteiro em centavos quando o repo já
adota essa convenção. Nunca `real`, `double precision`, `float` ou `money`.

Fonte: https://www.postgresql.org/docs/current/datatype-numeric.html,
https://www.postgresql.org/docs/current/datatype-money.html

## PG-SCH-003 Chave gerada com identity

Doc: `serial` não é um tipo, é notação para uma sequence mais um default. A alternativa padrão SQL é
`GENERATED { ALWAYS | BY DEFAULT } AS IDENTITY`. Com `ALWAYS`, o `INSERT` só aceita valor explícito
com `OVERRIDING SYSTEM VALUE`. Sequências deixam buracos: valor alocado por transação que fez
rollback não volta. Use a variante de 64 bits se a tabela puder passar de 2³¹ identificadores.

Harness: chave nova usa `bigint GENERATED ALWAYS AS IDENTITY`. `BY DEFAULT` só quando a carga de
dados precisa gravar o valor. Nenhuma regra de negócio depende de a sequência não ter buracos.

Fonte: https://www.postgresql.org/docs/current/sql-createtable.html,
https://www.postgresql.org/docs/current/datatype-numeric.html#DATATYPE-SERIAL

## PG-SCH-004 Texto sem limite arbitrário

Doc: não há diferença de desempenho entre `text`, `varchar(n)` e `char(n)`, exceto o espaço extra
de `char(n)` e o custo de checar o tamanho. `char(n)` costuma ser o mais lento. Para texto sem
limite específico, use `text` ou `varchar` sem tamanho em vez de inventar um limite.

Harness: `text` como padrão. Limite que é regra de negócio vira `CHECK`, que tem nome e mensagem
própria:

```sql
ALTER TABLE customers
    ADD CONSTRAINT customers_name_length CHECK (char_length(name) <= 200);
```

Fonte: https://www.postgresql.org/docs/current/datatype-character.html

## PG-SCH-005 `jsonb` no lugar de `json`

Doc: a maioria das aplicações deve preferir `jsonb`, salvo necessidade específica, como depender da
ordem das chaves do objeto.

Harness: campo que a query filtra com frequência vira coluna própria. `jsonb` guarda o que é de fato
variável. Consulta por conteúdo de `jsonb` usa índice GIN (ver `indexes.md`).

Fonte: https://www.postgresql.org/docs/current/datatype-json.html

## PG-SCH-006 `uuid` como tipo nativo

Doc: `uuid` armazena qualquer versão de UUID. O PostgreSQL gera UUIDv4 com `gen_random_uuid()` e,
a partir do 18, UUIDv7 com `uuidv7()`.

Harness: UUID é guardado como `uuid`, nunca como `text`. Com UUID como chave primária no 18 ou
superior, prefira `uuidv7()`. Abaixo do 18, a geração pode ficar na aplicação.

Fonte: https://www.postgresql.org/docs/current/datatype-uuid.html,
https://www.postgresql.org/docs/current/functions-uuid.html

## PG-SCH-007 `NOT NULL` como padrão

Doc: na maioria dos projetos, a maior parte das colunas deve ser `NOT NULL`. Uma FK não é checada
quando alguma coluna de referência é nula. Se isso não é desejado, declare as colunas `NOT NULL`.

Harness: toda coluna nasce `NOT NULL`. Coluna anulável precisa de significado claro para o NULL.

Fonte: https://www.postgresql.org/docs/current/ddl-constraints.html

## PG-SCH-008 Unicidade e NULL

Doc: por padrão, dois NULL não são considerados iguais numa constraint `UNIQUE`, então linhas
duplicadas com NULL passam. A partir do 15, `UNIQUE NULLS NOT DISTINCT` muda isso.

Harness: unicidade sobre coluna anulável declara a intenção. Abaixo do 15, use índice único parcial
ou torne a coluna `NOT NULL`.

Fonte: https://www.postgresql.org/docs/current/ddl-constraints.html#DDL-CONSTRAINTS-UNIQUE-CONSTRAINTS

## PG-SCH-009 FK com índice nas colunas de referência

Doc: a declaração de FK não cria índice nas colunas de referência. Um `DELETE` no pai, ou um `UPDATE`
da coluna referenciada, varre a tabela filha atrás das linhas que apontam para o valor antigo. Por
isso costuma valer indexar as colunas de referência.

Harness: toda FK tem índice começando pelas colunas de referência quando o pai sofre `DELETE` ou
`UPDATE` da chave, ou quando a FK entra em join. A exceção precisa de justificativa no PR.

```sql
CREATE INDEX CONCURRENTLY order_items_order_id_idx ON order_items (order_id);
```

Fonte: https://www.postgresql.org/docs/current/ddl-constraints.html#DDL-CONSTRAINTS-FK
