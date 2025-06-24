SELECT n.n_name, SUM(l.l_extendedprice * (1 - l.l_discount)) AS revenue
FROM customer c
JOIN orders o ON c.c_custkey = o.o_custkey
JOIN lineitem l ON o.o_orderkey = l.l_orderkey
JOIN supplier s ON l.l_suppkey = s.s_suppkey
JOIN partsupp ps ON l.l_partkey = ps.ps_partkey AND s.s_suppkey = ps.ps_suppkey
JOIN part p ON ps.ps_partkey = p.p_partkey
JOIN nation n ON s.s_nationkey = n.n_nationkey
WHERE o.o_orderdate >= DATE '2023-01-01'
  AND o.o_orderdate < DATE '2024-01-01'
GROUP BY n.n_name
ORDER BY revenue DESC
LIMIT 10;
