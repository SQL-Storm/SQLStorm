SELECT 
    l_shipmode,
    COUNT(*) AS order_count,
    SUM(l_extendedprice) AS total_revenue
FROM 
    lineitem
WHERE 
    l_shipdate BETWEEN DATE '2023-01-01' AND DATE '2023-12-31'
GROUP BY 
    l_shipmode
ORDER BY 
    order_count DESC;
