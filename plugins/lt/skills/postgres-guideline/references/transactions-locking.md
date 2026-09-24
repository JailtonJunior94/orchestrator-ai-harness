# Transações e locks

<!-- TL;DR
Read Committed é o padrão, Repeatable Read e Serializable exigem retry da transação inteira em 40001, retry de deadlock em 40P01, locks em ordem consistente, FOR UPDATE com NOWAIT ou SKIP LOCKED para fila, advisory lock com escopo de transação, transação curta.
Keywords: BEGIN, COMMIT, ISOLATION LEVEL, SERIALIZABLE, REPEATABLE READ, 40001, 40P01, 23505, deadlock, FOR UPDATE, SKIP LOCKED, NOWAIT, pg_advisory_xact_lock, LOCK TABLE
Load complete when: a mudança abre transação, escolhe isolamento, trata erro de concorrência, trava linha ou implementa fila ou exclusão mútua.
-->

- Escopo: código de aplicação que abre transação ou coordena escrita concorrente.
- Para o lock que cada `ALTER TABLE` pega, ver `migrations.md`.

## Sumário

- PG-TX-001 Isolamento explícito quando não é Read Committed
- PG-TX-002 Retry da transação inteira
- PG-TX-003 Locks em ordem consistente
- PG-TX-004 Fila com `FOR UPDATE SKIP LOCKED`
- PG-TX-005 Advisory lock com escopo de transação
- PG-TX-006 Transação curta

## PG-TX-001 Isolamento explícito quando não é Read Committed

Doc: Read Committed é o nível padrão. Nele, cada comando vê só o que foi confirmado antes de ele
começar, então dois `SELECT` na mesma transação podem ver dados diferentes. Repeatable Read e
Serializable dão garantias maiores, e quem os usa precisa estar preparado para repetir a transação
em falha de serialização.

Harness: o código declara o nível quando não é o padrão, e a escolha tem motivo (invariante que
atravessa várias linhas ou leitura consistente de relatório).

Fonte: https://www.postgresql.org/docs/current/transaction-iso.html

## PG-TX-002 Retry da transação inteira

Doc: falha de serialização sempre tem SQLSTATE `40001` (`serialization_failure`). Também pode valer
repetir deadlock, `40P01` (`deadlock_detected`). Em alguns casos, `23505` (`unique_violation`) e
`23P01` (`exclusion_violation`) são, na prática, falha de serialização, por exemplo quando a
aplicação escolhe a chave depois de ler as existentes. A repetição é da transação inteira, inclusive
a lógica que decide o SQL e os valores, e o PostgreSQL não faz retry automático. Pode ser preciso
repetir várias vezes.

Harness: o retry fica em volta da função que abre e fecha a transação, com limite de tentativas e
espera crescente com jitter. Compare pelo SQLSTATE, nunca pelo texto da mensagem. Exemplo em Go
com pgx v5:

```go
for attempt := 1; ; attempt++ {
	err := runInTx(ctx, db, transfer)
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && (pgErr.Code == "40001" || pgErr.Code == "40P01") && attempt < maxAttempts {
		sleepWithJitter(ctx, attempt)
		continue
	}
	return err
}
```

Fonte: https://www.postgresql.org/docs/current/mvcc-serialization-failure-handling.html,
https://www.postgresql.org/docs/current/errcodes-appendix.html

## PG-TX-003 Locks em ordem consistente

Doc: deadlock pode acontecer só com locks de linha, sem lock explícito. O PostgreSQL detecta e
aborta uma das transações. A melhor defesa é todas as aplicações adquirirem locks em vários objetos
sempre na mesma ordem, e o primeiro lock num objeto já ser o modo mais restritivo que a transação
vai precisar.

Harness: atualização de várias linhas numa transação ordena pela chave (`ORDER BY id` no
`SELECT ... FOR UPDATE`, ou ordenação dos IDs na aplicação antes do laço).

Fonte: https://www.postgresql.org/docs/current/explicit-locking.html#LOCKING-DEADLOCKS

## PG-TX-004 Fila com `FOR UPDATE SKIP LOCKED`

Doc: `NOWAIT` faz o comando falhar em vez de esperar pela linha travada. `SKIP LOCKED` pula as linhas
que não pode travar na hora. Pular linhas dá uma visão inconsistente dos dados, então não serve para
uso geral, mas evita contenção com vários consumidores de uma tabela usada como fila.

```sql
SELECT id, payload FROM jobs
WHERE status = 'pending'
ORDER BY run_at
LIMIT 10
FOR UPDATE SKIP LOCKED;
```

Fonte: https://www.postgresql.org/docs/current/sql-select.html#SQL-FOR-UPDATE-SHARE

## PG-TX-005 Advisory lock com escopo de transação

Doc: advisory lock tem significado definido pela aplicação e o sistema não força seu uso. Lock de
sessão fica até ser liberado ou a sessão acabar, inclusive se a transação que o pegou fizer
rollback. Lock de transação é liberado no fim da transação. Com `LIMIT` e ordenação, a ordem de
avaliação pode travar mais linhas que as devolvidas.

Harness: prefira `pg_advisory_xact_lock`. Lock de sessão atrás de pooler em modo transação pode
ficar preso numa conexão que outra requisição vai reusar.

Fonte: https://www.postgresql.org/docs/current/explicit-locking.html#ADVISORY-LOCKS

## PG-TX-006 Transação curta

Doc: sessão ociosa dentro de transação segura locks e, mesmo sem lock relevante, impede o vacuum de
remover tuplas mortas que só ela ainda poderia ver, o que incha a tabela.

Harness: nada de chamada HTTP, fila externa, espera de usuário ou laço sem limite com transação
aberta. Limites de tempo em `connections-observability.md`.

Fonte: https://www.postgresql.org/docs/current/runtime-config-client.html#GUC-IDLE-IN-TRANSACTION-SESSION-TIMEOUT
