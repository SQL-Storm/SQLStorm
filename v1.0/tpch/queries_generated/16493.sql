SELECT p_name, SUM(l_extendedprice * (1 - l_discount)) AS total_revenue
FROM part
JOIN lineitem ON part.p_partkey = lineitem.l_partkey
WHERE lineitem.l_shipdate >= '2023-01-01' AND lineitem.l_shipdate < '2023-12-31'
GROUP BY p_name
ORDER BY total_revenue DESC
LIMIT 10;
