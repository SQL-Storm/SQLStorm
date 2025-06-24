SELECT l_orderkey, SUM(l_extendedprice) AS total_revenue
FROM lineitem
WHERE l_shipdate >= '2023-01-01'
GROUP BY l_orderkey
ORDER BY total_revenue DESC
LIMIT 10;
