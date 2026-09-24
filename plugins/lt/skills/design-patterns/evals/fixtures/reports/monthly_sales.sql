SELECT s.region, SUM(s.amount) AS total
FROM sales s
JOIN customers c ON c.id = s.customer_id
WHERE s.created_at BETWEEN '2026-08-01' AND '2026-08-31'
GROUP BY s.region;
