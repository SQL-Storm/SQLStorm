SELECT p.p_name, SUM(l.l_extendedprice * (1 - l.l_discount)) AS revenue
FROM part p
JOIN lineitem l ON p.p_partkey = l.l_partkey
JOIN supplier s ON l.l_suppkey = s.s_suppkey
JOIN partsupp ps ON p.p_partkey = ps.ps_partkey AND s.s_suppkey = ps.ps_suppkey
JOIN customer c ON c.c_custkey = o.o_custkey
JOIN orders o ON o.o_orderkey = l.l_orderkey
WHERE c.c_mktsegment = 'BUILDING'
GROUP BY p.p_name
ORDER BY revenue DESC
LIMIT 10;
