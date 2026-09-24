# Segurança

<!-- TL;DR
Parâmetro de bind contra SQL injection, identificador dinâmico com format %I, role da aplicação sem superusuário nem BYPASSRLS e sem ser dona das tabelas, CREATE no schema public revogado, RLS com FORCE, SECURITY DEFINER com search_path fixo e EXECUTE revogado de PUBLIC, SCRAM no lugar de MD5.
Keywords: GRANT, REVOKE, ROLE, BYPASSRLS, ROW LEVEL SECURITY, POLICY, search_path, SECURITY DEFINER, EXECUTE format, quote_ident, quote_literal, scram-sha-256, md5
Load complete when: a mudança monta SQL dinâmico, cria role ou função, concede privilégio, ativa RLS ou mexe em autenticação.
-->

- Escopo: SQL da aplicação, funções no banco, roles e privilégios definidos em migração.
- Credencial nunca vai no repositório nem em DSN de exemplo (`R-SEC`).

## Sumário

- PG-SEC-001 Valor por parâmetro, nunca por concatenação
- PG-SEC-002 SQL dinâmico em PL/pgSQL
- PG-SEC-003 Role da aplicação com privilégio mínimo
- PG-SEC-004 Schema `public` sem `CREATE` para todos
- PG-SEC-005 Row level security
- PG-SEC-006 `SECURITY DEFINER` seguro
- PG-SEC-007 Autenticação SCRAM

## PG-SEC-001 Valor por parâmetro, nunca por concatenação

Doc: a vantagem principal de enviar parâmetros separados do texto do comando é evitar o escape de
aspas, trabalhoso e sujeito a erro.

Harness: todo valor externo entra como parâmetro (`$1`) do driver. Concatenar ou interpolar valor em
SQL é defeito de segurança, mesmo que o valor pareça confiável.

Fonte: https://www.postgresql.org/docs/current/libpq-exec.html

## PG-SEC-002 SQL dinâmico em PL/pgSQL

Doc: em `EXECUTE`, valor entra por `USING`. Identificador (tabela, coluna) passa por
`format('%I')` ou `quote_ident`. Literal que precisa ir no texto passa por `format('%L')` ou
`quote_literal`.

```sql
EXECUTE format('UPDATE %I SET %I = $1 WHERE id = $2', tbl, col) USING new_value, row_id;
```

Harness: identificador dinâmico vindo de fora também é validado contra uma lista permitida antes do
`format`, porque `%I` impede injection mas não impede acesso a outra tabela.

Fonte: https://www.postgresql.org/docs/current/plpgsql-statements.html#PLPGSQL-STATEMENTS-EXECUTING-DYN

## PG-SEC-003 Role da aplicação com privilégio mínimo

Doc: superusuário e role com `BYPASSRLS` sempre ignoram row level security. O dono da tabela
normalmente também. Na maioria dos tipos de objeto, só o dono (ou um superusuário) pode usá-lo até
que conceda privilégio. Função é exceção: `EXECUTE` nasce concedido a `PUBLIC` (PG-SEC-006).

Harness: a aplicação usa uma role que não é superusuário, não tem `BYPASSRLS` e não é dona das
tabelas. Migração roda com outra role, dona do schema. A role da aplicação recebe só o que usa:

```sql
GRANT USAGE ON SCHEMA app TO app_rw;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app TO app_rw;
ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA app
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_rw;
```

Fonte: https://www.postgresql.org/docs/current/ddl-priv.html,
https://www.postgresql.org/docs/current/ddl-rowsecurity.html

## PG-SEC-004 Schema `public` sem `CREATE` para todos

Doc: em banco atualizado a partir do PostgreSQL 14 ou anterior, todo usuário tem `CREATE` no schema
`public`. Um padrão seguro de schema impede que usuário não confiável mude o comportamento das
queries de outro usuário, por exemplo criando um objeto com o mesmo nome num schema que vem antes no
`search_path`.

```sql
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
```

Fonte: https://www.postgresql.org/docs/current/ddl-schemas.html#DDL-SCHEMAS-PRIV,
https://www.postgresql.org/docs/current/ddl-schemas.html#DDL-SCHEMAS-PATTERNS

## PG-SEC-005 Row level security

Doc: com RLS ativo, todo acesso às linhas precisa ser permitido por uma policy. Sem policy, vale
negação total. O dono da tabela ignora as policies, a menos que a tabela use
`FORCE ROW LEVEL SECURITY`.

Harness: tabela multi-inquilino com RLS usa `ENABLE` e `FORCE`, e o teste cobre o acesso com a role
da aplicação, não com a role dona.

```sql
ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoices FORCE ROW LEVEL SECURITY;
CREATE POLICY invoices_tenant ON invoices
    USING (tenant_id = current_setting('app.tenant_id')::bigint);
```

Fonte: https://www.postgresql.org/docs/current/ddl-rowsecurity.html

## PG-SEC-006 `SECURITY DEFINER` seguro

Doc: função `SECURITY DEFINER` roda com o privilégio do dono. O `search_path` dela deve excluir
schemas graváveis por usuário não confiável, com `pg_temp` por último, senão uma tabela temporária
com o mesmo nome desvia a função. Por padrão, `EXECUTE` de função nova é concedido a `PUBLIC`.

```sql
CREATE FUNCTION app.close_invoice(invoice_id bigint) RETURNS void
    LANGUAGE sql
    SECURITY DEFINER
    SET search_path = app, pg_temp
    AS $$ UPDATE app.invoices SET status = 'closed' WHERE id = invoice_id $$;
REVOKE ALL ON FUNCTION app.close_invoice(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app.close_invoice(bigint) TO app_rw;
```

Fonte: https://www.postgresql.org/docs/current/sql-createfunction.html#SQL-CREATEFUNCTION-SECURITY

## PG-SEC-007 Autenticação SCRAM

Doc: `scram-sha-256` evita a captura de senha em conexão não confiável e guarda a senha com hash
considerado seguro. O suporte a senha MD5 está obsoleto e será removido numa versão futura.

Harness: `password_encryption = 'scram-sha-256'` e `pg_hba.conf` com `scram-sha-256`. Configuração
nova com `md5` é defeito.

Fonte: https://www.postgresql.org/docs/current/auth-password.html
