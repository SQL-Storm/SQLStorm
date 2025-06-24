SELECT p.p_partkey, p.p_name, sum(l.l_extendedprice * (1 - l.l_discount)) as revenue
FROM part p
JOIN lineitem l ON p.p_partkey = l.l_partkey
WHERE l.l_shipdate >= '2023-01-01' AND l.l_shipdate < '2023-12-31'
GROUP BY p.p_partkey, p.p_name
ORDER BY revenue DESC
LIMIT 10;
