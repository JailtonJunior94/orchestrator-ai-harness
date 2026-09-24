Revisa a migração evals/fixtures/migrations/0042_orders_customer.sql antes de rodar no PostgreSQL de produção. A tabela orders tem uns 200 milhões de linhas e recebe escrita o tempo todo.

O repositório não está disponível nesta sessão; o conteúdo atual dos arquivos citados vai abaixo.

`evals/fixtures/migrations/0042_orders_customer.sql`:

```
ALTER TABLE orders ADD COLUMN customer_id bigint;

ALTER TABLE orders
    ADD CONSTRAINT orders_customer_id_fkey
    FOREIGN KEY (customer_id) REFERENCES customers (id);

CREATE INDEX orders_customer_id_idx ON orders (customer_id);

ALTER TABLE orders ALTER COLUMN total TYPE numeric(14, 2);

ALTER TABLE orders ALTER COLUMN status SET NOT NULL;
```
