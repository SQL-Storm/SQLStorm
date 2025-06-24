SELECT p.p_name, SUM(l.l_extendedprice * (1 - l.l_discount)) AS revenue
FROM lineitem l
JOIN partsupp ps ON l.l_partkey = ps.ps_partkey
JOIN part p ON ps.ps_partkey = p.p_partkey
WHERE l.l_shipdate >= '2023-01-01' AND l.l_shipdate < '2024-01-01'
GROUP BY p.p_name
ORDER BY revenue DESC
LIMIT 10;
