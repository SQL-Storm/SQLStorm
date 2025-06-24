SELECT l_linenumber, SUM(l_extendedprice) AS total_revenue
FROM lineitem
WHERE l_shipdate >= '2023-01-01' AND l_shipdate < '2023-12-31'
GROUP BY l_linenumber
ORDER BY total_revenue DESC
LIMIT 10;
