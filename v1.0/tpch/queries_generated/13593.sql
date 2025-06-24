SELECT 
    l_suppkey, 
    SUM(l_extendedprice * (1 - l_discount)) AS total_revenue
FROM 
    lineitem
WHERE 
    l_shipdate >= DATE '2023-01-01' AND 
    l_shipdate < DATE '2023-12-31'
GROUP BY 
    l_suppkey
ORDER BY 
    total_revenue DESC
LIMIT 10;
