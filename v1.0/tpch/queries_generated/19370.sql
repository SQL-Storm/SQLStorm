SELECT c.c_name, SUM(l.l_extendedprice * (1 - l.l_discount)) AS total_revenue
FROM customer c
JOIN orders o ON c.c_custkey = o.o_custkey
JOIN lineitem l ON o.o_orderkey = l.l_orderkey
WHERE o.o_orderdate BETWEEN '2023-01-01' AND '2023-12-31'
GROUP BY c.c_name
ORDER BY total_revenue DESC
LIMIT 10;
