SELECT 
    c.c_mktsegment,
    SUM(l.l_extendedprice * (1 - l.l_discount)) AS total_revenue
FROM 
    customer c
JOIN 
    orders o ON c.c_custkey = o.o_custkey
JOIN 
    lineitem l ON o.o_orderkey = l.l_orderkey
WHERE 
    o.o_orderdate >= DATE '2023-01-01' AND o.o_orderdate < DATE '2024-01-01'
GROUP BY 
    c.c_mktsegment
ORDER BY 
    total_revenue DESC
LIMIT 10;
