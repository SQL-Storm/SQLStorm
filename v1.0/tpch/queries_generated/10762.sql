SELECT 
    l_orderkey, 
    SUM(l_extendedprice * (1 - l_discount)) AS revenue, 
    o_orderdate, 
    o_orderpriority 
FROM 
    lineitem 
JOIN 
    orders ON l_orderkey = o_orderkey 
WHERE 
    l_shipdate >= DATE '2023-01-01' 
    AND l_shipdate < DATE '2023-12-31' 
GROUP BY 
    l_orderkey, 
    o_orderdate, 
    o_orderpriority 
ORDER BY 
    revenue DESC 
LIMIT 10;
