SELECT p_name, SUM(l_extendedprice) AS total_revenue
FROM part
JOIN partsupp ON part.p_partkey = partsupp.ps_partkey
JOIN lineitem ON partsupp.ps_suppkey = lineitem.l_suppkey
WHERE lineitem.l_shipdate >= '2023-01-01' AND lineitem.l_shipdate < '2024-01-01'
GROUP BY p_name
ORDER BY total_revenue DESC
LIMIT 10;
