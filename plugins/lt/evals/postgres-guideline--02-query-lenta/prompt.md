A listagem de pedidos do cliente ficou lenta no PostgreSQL. A query está em evals/fixtures/orders/list_orders.sql e o EXPLAIN (ANALYZE, BUFFERS) em evals/fixtures/orders/explain.txt. O que eu faço?

O repositório não está disponível nesta sessão; o conteúdo atual dos arquivos citados vai abaixo.

`evals/fixtures/orders/list_orders.sql`:

```
SELECT id, created_at, total
FROM orders
WHERE customer_id = $1
ORDER BY created_at DESC
LIMIT 50 OFFSET $2;
```

`evals/fixtures/orders/explain.txt`:

```
Limit  (cost=412883.10..412883.23 rows=50 width=30) (actual time=2381.442..2381.455 rows=50 loops=1)
  Buffers: shared hit=1204 read=187342
  ->  Sort  (cost=412858.10..412953.61 rows=38204 width=30) (actual time=2380.911..2381.297 rows=10050 loops=1)
        Sort Key: created_at DESC
        Sort Method: top-N heapsort  Memory: 1872kB
        Buffers: shared hit=1204 read=187342
        ->  Seq Scan on orders  (cost=0.00..410447.00 rows=38204 width=30) (actual time=0.412..2365.108 rows=41877 loops=1)
              Filter: (customer_id = 81234)
              Rows Removed by Filter: 18958123
              Buffers: shared hit=1204 read=187342
Planning Time: 0.118 ms
Execution Time: 2381.502 ms
```
