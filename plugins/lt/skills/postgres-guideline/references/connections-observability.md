# Conexões, timeouts e observabilidade

<!-- TL;DR
Timeouts por role ou sessão e não no postgresql.conf, max_connections limitado e pool na aplicação, idle_session_timeout com cuidado atrás de pooler, transação aberta impede vacuum, pg_stat_statements e auto_explain exigem preload, pg_stat_activity e pg_blocking_pids para achar bloqueio.
Keywords: statement_timeout, lock_timeout, idle_in_transaction_session_timeout, transaction_timeout, idle_session_timeout, max_connections, pool, autovacuum, pg_stat_statements, auto_explain, pg_stat_activity, pg_locks, pg_blocking_pids
Load complete when: a mudança configura driver, pool ou timeout, ou investiga lentidão, bloqueio ou inchaço em produção.
-->

- Escopo: o que a aplicação configura na conexão e o que ela usa para diagnosticar o banco.
- Tuning de servidor (memória, WAL, checkpoint, replicação) está fora do escopo desta skill.

## Sumário

- PG-OPS-001 Timeouts por role ou sessão
- PG-OPS-002 Conexões limitadas e pool
- PG-OPS-003 Transação aberta impede vacuum
- PG-OPS-004 Encontrar a query cara
- PG-OPS-005 Encontrar quem bloqueia

## PG-OPS-001 Timeouts por role ou sessão

Doc: `statement_timeout`, `lock_timeout` e `transaction_timeout` (este a partir do 17) têm padrão
zero, que desliga o limite, e a documentação não recomenda defini-los no `postgresql.conf`, porque
afetariam todas as sessões. `idle_in_transaction_session_timeout` encerra a sessão ociosa dentro de
transação. `idle_session_timeout` encerra a sessão ociosa fora de transação, e a documentação pede
cuidado com ele atrás de pooler, que pode não reagir bem ao fechamento inesperado da conexão.

Harness: a role da aplicação tem `statement_timeout` e `idle_in_transaction_session_timeout`
definidos, com valores tirados do SLO da operação:

```sql
ALTER ROLE app_rw SET statement_timeout = '5s';
ALTER ROLE app_rw SET idle_in_transaction_session_timeout = '30s';
```

Job e relatório longos usam outra role ou `SET LOCAL` na própria transação.

Fonte: https://www.postgresql.org/docs/current/runtime-config-client.html#RUNTIME-CONFIG-CLIENT-STATEMENT

## PG-OPS-002 Conexões limitadas e pool

Doc: `max_connections` define o máximo de conexões simultâneas, normalmente 100, e só muda com
reinício do servidor.

Harness: toda instância da aplicação usa pool com tamanho máximo explícito. A soma dos pools de
todas as instâncias e jobs fica abaixo de `max_connections`, com folga para migração e acesso
administrativo.

Prática: com muitas instâncias, um pooler externo (fora da documentação do PostgreSQL) concentra as
conexões. Em modo transação, estado de sessão (`SET` sem `LOCAL`, advisory lock de sessão, prepared
statement nomeado) não sobrevive entre transações: confirme o que o pooler e o driver suportam.

Fonte: https://www.postgresql.org/docs/current/runtime-config-connection.html#GUC-MAX-CONNECTIONS

## PG-OPS-003 Transação aberta impede vacuum

Doc: uma transação aberta impede o vacuum de remover tuplas mortas que ainda podem ser visíveis
para ela, o que contribui para inchaço da tabela. Para muitas instalações, basta deixar o vacuum a
cargo do autovacuum. Vacuum por agenda fixa não acompanha um pico inesperado de atualização.

Harness: não desligue o autovacuum de tabela. Inchaço persistente se investiga pela transação mais
antiga em `pg_stat_activity` (`xact_start`) antes de mexer em configuração.

Fonte: https://www.postgresql.org/docs/current/routine-vacuuming.html,
https://www.postgresql.org/docs/current/runtime-config-client.html#GUC-IDLE-IN-TRANSACTION-SESSION-TIMEOUT

## PG-OPS-004 Encontrar a query cara

Doc: `pg_stat_statements` acumula estatística de planejamento e execução por query e precisa estar
em `shared_preload_libraries`, o que exige reinício. `auto_explain` registra o plano de queries
lentas e não faz nada até `auto_explain.log_min_duration` ser definido.

Harness: a otimização começa pelas queries com maior `total_exec_time` em `pg_stat_statements`, não
pela que parece lenta.

```sql
SELECT queryid, calls, total_exec_time, mean_exec_time, rows, query
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 20;
```

Fonte: https://www.postgresql.org/docs/current/pgstatstatements.html,
https://www.postgresql.org/docs/current/auto-explain.html

## PG-OPS-005 Encontrar quem bloqueia

Doc: `pg_blocking_pids(pid)` devolve os processos que impedem outro de pegar um lock. `pg_locks`
lista os locks, inclusive advisory.

```sql
SELECT pid, pg_blocking_pids(pid) AS blocked_by, wait_event_type, state, xact_start, query
FROM pg_stat_activity
WHERE cardinality(pg_blocking_pids(pid)) > 0;
```

Fonte: https://www.postgresql.org/docs/current/functions-info.html,
https://www.postgresql.org/docs/current/monitoring-stats.html#MONITORING-PG-STAT-ACTIVITY-VIEW
