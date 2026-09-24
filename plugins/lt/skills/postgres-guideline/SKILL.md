---
name: postgres-guideline
description: Diretrizes de produção para PostgreSQL com a documentação oficial como fonte (schema, índices, EXPLAIN, locks, migração sem downtime e segurança). Use ao escrever, revisar ou otimizar DDL, migração ou query em projeto com PostgreSQL, em qualquer linguagem. Não use para MySQL, SQLite, SQL Server ou outro banco.
metadata:
  version: 1.0.0
  category: processual
---

# Diretrizes PostgreSQL

Piso de qualidade para schema, migração e query que vão rodar em PostgreSQL de produção. As regras
vêm da [documentação oficial](https://www.postgresql.org/docs/current/). Cada regra nas referências
diz de onde veio:

- `Doc:` a documentação afirma isso. A linha `Fonte:` aponta a seção.
- `Harness:` decisão deste harness derivada do comportamento documentado. O motivo vem junto.
- `Prática:` prática de mercado que a documentação não cobre (pooler externo, expand/contract).
  Nunca é atribuída à documentação.

## Precedência

1. A constitution do harness (`R-STYLE-001`, `R-SEC`, `R-ERR`): regra hard vence qualquer fonte externa.
2. A documentação oficial **da versão que o projeto usa** (`https://www.postgresql.org/docs/<versão>/`).
3. As regras `Harness:` e `Prática:` desta skill.
4. A convenção já estabelecida no repositório, desde que não contradiga os itens acima.

## Versão alvo

A versão decide quais recursos existem. Descubra nesta ordem e pare na primeira que responder:

1. Imagem ou serviço declarado no repo (`docker-compose*.yml`, `Dockerfile`, IaC, CI).
2. Documentação do projeto ou configuração do driver.
3. Com acesso ao banco: `SHOW server_version_num;`.

Sem resposta, assuma a **menor versão com suporte oficial** listada em
<https://www.postgresql.org/support/versioning/> e registre a suposição. Recurso que exige versão
maior só entra marcado com a versão mínima:

| Recurso | Desde |
|---|---|
| `UNIQUE NULLS NOT DISTINCT` | 15 |
| Schema `public` sem `CREATE` para `PUBLIC` em banco novo | 15 |
| `transaction_timeout` | 17 |
| `uuidv7()` | 18 |
| `EXPLAIN ANALYZE` inclui `BUFFERS` sem pedir | 18 |
| `NOT VALID` em constraint `NOT NULL` | 18 |
| Skip scan em índice B-tree multicoluna | 18 |

## Piso inegociável

Toda mudança que toca PostgreSQL cumpre estas regras, sem precisar abrir nenhuma referência:

1. Valor vindo de fora entra por parâmetro de bind (`$1`), nunca por concatenação. Identificador
   dinâmico passa por `format('%I')` ou `quote_ident`.
2. Instante no tempo é `timestamptz`. Dinheiro e valor exato são `numeric`, nunca `real`,
   `double precision` ou `money`.
3. Chave gerada usa `GENERATED ... AS IDENTITY` (`bigint` quando a tabela pode passar de 2³¹ linhas),
   não `serial`.
4. Texto é `text` ou `varchar` sem limite, com `CHECK (char_length(...) <= n)` quando o limite é
   regra de negócio. Nada de `varchar(255)` por hábito.
5. Coluna é `NOT NULL` salvo motivo explícito. Toda FK tem índice nas colunas de referência quando
   o pai sofre `DELETE` ou `UPDATE` da chave, ou quando a FK entra em join.
6. DDL em tabela com tráfego começa com `SET lock_timeout` curto e aceita ser repetida.
7. Índice em tabela com tráfego usa `CREATE INDEX CONCURRENTLY`, fora de bloco de transação, e a
   migração confere se sobrou índice `INVALID`.
8. FK, `CHECK` e (no 18 ou superior) `NOT NULL` novos em tabela grande entram com `NOT VALID` e
   depois `VALIDATE CONSTRAINT`, em transações separadas.
9. Mudança que reescreve a tabela (`ALTER COLUMN TYPE` não binário-compatível, `ADD COLUMN` com
   default volátil) não roda em tabela grande com tráfego sem plano de expand/contract.
10. Transação curta: nada de chamada de rede, espera de usuário ou lote sem limite com transação aberta.
11. Código em `REPEATABLE READ` ou `SERIALIZABLE` repete a transação inteira em `40001`. Todo código
    que pode sofrer deadlock repete em `40P01`, com limite de tentativas.
12. Query nova em caminho quente tem `EXPLAIN (ANALYZE, BUFFERS)` medido em volume realista. DML
    medido com `EXPLAIN ANALYZE` roda entre `BEGIN` e `ROLLBACK`.
13. A aplicação conecta com role sem superusuário, sem `BYPASSRLS` e sem ser dona do schema.
14. Função `SECURITY DEFINER` tem `SET search_path` fixo terminando em `pg_temp` e `EXECUTE`
    revogado de `PUBLIC`.

## Referências

Abra só a referência que a mudança exige. Para descobrir quais casam com os arquivos tocados
(`AGENTS_ROOT` é o diretório que contém `skills/`, dois níveis acima desta skill em qualquer host):

```bash
git diff | AGENTS_ROOT="${CLAUDE_SKILL_DIR}/../.." bash "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-references.sh" postgres-guideline <arquivos tocados>
```

| Tarefa | Referência |
|---|---|
| Tipo de coluna, chave, constraint, NULL, `jsonb`, `uuid` | `references/schema-design.md` |
| Criar, escolher ou remover índice; índice parcial, de expressão, `INCLUDE`, GIN, BRIN | `references/indexes.md` |
| Query lenta, `EXPLAIN`, estatísticas, paginação, `NOT IN`, CTE, carga em lote | `references/queries.md` |
| Isolamento, retry, deadlock, `FOR UPDATE`, `SKIP LOCKED`, advisory lock | `references/transactions-locking.md` |
| Arquivo de migração, `ALTER TABLE`, índice concorrente, constraint `NOT VALID`, backfill | `references/migrations.md` |
| Roles, `GRANT`, RLS, `search_path`, `SECURITY DEFINER`, SQL dinâmico, autenticação | `references/security.md` |
| Timeouts, conexões, pool, vacuum, `pg_stat_statements`, diagnóstico de lock | `references/connections-observability.md` |

## Procedimentos

**Etapa 1: Ler o contexto**
1. Determinar a versão alvo (seção acima).
2. Identificar a ferramenta de migração do repo e o formato que ela exige (transação implícita por
   arquivo ou não). `CREATE INDEX CONCURRENTLY` falha dentro de bloco de transação.
3. Ler o schema atual das tabelas tocadas: migrações anteriores, `schema.sql` ou `\d+ tabela`.

**Etapa 2: Carregar as regras certas**
1. Aplicar o piso inegociável sempre.
2. Rodar o `resolve-references.sh` acima e abrir apenas as referências listadas. Sem o script,
   escolher pela tabela de referências.

**Etapa 3: Implementar**
1. Escrever a menor mudança que resolve o pedido, seguindo as referências carregadas.
2. SQL, identificadores e mensagens em inglês (`R-STYLE-001.1`), sem comentário no código produzido
   (`R-STYLE-001.2`).
3. Não adicionar extensão nem dependência para algo que o PostgreSQL já resolve.

**Etapa 4: Validar**

Rodar o que existir no ambiente, contra banco descartável, nunca contra produção:

1. A suíte de testes do repo e o linter de SQL ou de migração que o repo já configura.
2. A migração nova aplicada do zero e, quando a ferramenta suporta, revertida.
3. `EXPLAIN (ANALYZE, BUFFERS)` das queries novas ou alteradas, com volume realista.
4. Depois de índice concorrente: `SELECT indexrelid::regclass FROM pg_index WHERE NOT indisvalid;`
   não devolve nada.

Comando que não pôde rodar é reportado como `não verificado`, com o motivo. Nunca como aprovado.
Falha é reportada com o comando exato e a primeira mensagem relevante.

**Etapa 5: Revisar a própria mudança**
1. Conferir o diff contra o piso inegociável.
2. Para cada `ALTER TABLE`, anotar o lock que ele pega e se reescreve a tabela.
3. Registrar cada desvio intencional com o ID da regra (`PG-MIG-003`, por exemplo) e o motivo.

## Tratamento de Erros

- Pedido que exige violar o piso (por exemplo, "cria o índice direto, sem concurrently"): explicar
  a regra, propor a alternativa conforme e só seguir o pedido original se a pessoa confirmar.
- Regra do repo que contradiz esta skill: seguir o repo no arquivo tocado, apontar a divergência no
  relatório e não reescrever o resto por conta própria.
- Dúvida sobre comportamento do PostgreSQL: consultar a página da versão alvo em
  `https://www.postgresql.org/docs/<versão>/` antes de afirmar. Sem acesso, dizer que não foi
  verificado em vez de responder de memória.
- Banco que não é PostgreSQL (MySQL, SQLite, SQL Server, Oracle): esta skill não se aplica.

## Atribuição

As regras `Doc:` são adaptadas da documentação do PostgreSQL, Portions Copyright © 1996-2026
PostgreSQL Global Development Group, distribuída sob a
[PostgreSQL License](https://www.postgresql.org/docs/current/legalnotice.html). A tradução e as
regras `Harness:` e `Prática:` são deste harness.
