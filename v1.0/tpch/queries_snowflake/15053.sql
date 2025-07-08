SELECT p_brand, SUM(l_extendedprice) AS total_revenue
FROM part
JOIN partsupp ON p_partkey = ps_partkey
JOIN lineitem ON ps_partkey = l_partkey
GROUP BY p_brand
ORDER BY total_revenue DESC
LIMIT 10;
