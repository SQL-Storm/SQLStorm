SELECT l_shipmode, COUNT(*) AS shipping_count, SUM(l_extendedprice) AS total_revenue
FROM lineitem
WHERE l_shipdate BETWEEN '2022-01-01' AND '2022-12-31'
GROUP BY l_shipmode
ORDER BY total_revenue DESC;
