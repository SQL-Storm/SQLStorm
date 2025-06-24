SELECT 
    l_shipmode, 
    COUNT(*) AS order_count, 
    SUM(l_extendedprice * (1 - l_discount)) AS total_revenue 
FROM 
    lineitem 
WHERE 
    l_shipdate >= DATE '1997-01-01' 
    AND l_shipdate < DATE '1997-10-01' 
GROUP BY 
    l_shipmode 
ORDER BY 
    order_count DESC;