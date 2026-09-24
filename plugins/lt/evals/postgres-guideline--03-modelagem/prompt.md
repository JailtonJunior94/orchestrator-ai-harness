Vou criar a tabela de faturas no nosso PostgreSQL com o DDL de evals/fixtures/billing/schema.sql. Está bom para produção? Mostra como deveria ficar.

O repositório não está disponível nesta sessão; o conteúdo atual dos arquivos citados vai abaixo.

`evals/fixtures/billing/schema.sql`:

```
CREATE TABLE invoices (
    id serial PRIMARY KEY,
    customer_email varchar(255),
    amount float,
    currency varchar(255),
    issued_at timestamp,
    paid_at timestamp
);
```
