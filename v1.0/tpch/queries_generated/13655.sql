SELECT 
    l_shipmode, 
    COUNT(DISTINCT o_orderkey) AS order_count, 
    SUM(l_extendedprice * (1 - l_discount)) AS total_revenue 
FROM 
    lineitem 
JOIN 
    orders ON l_orderkey = o_orderkey 
WHERE 
    l_shipdate >= '2023-01-01' 
    AND l_shipdate < '2024-01-01' 
GROUP BY 
    l_shipmode 
ORDER BY 
    total_revenue DESC;
