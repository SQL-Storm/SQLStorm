SELECT 
    p.p_name,
    SUM(l.l_extendedprice) AS total_revenue,
    COUNT(DISTINCT o.o_orderkey) AS order_count,
    AVG(l.l_discount) AS average_discount
FROM 
    part p
JOIN 
    lineitem l ON p.p_partkey = l.l_partkey
JOIN 
    orders o ON l.l_orderkey = o.o_orderkey
WHERE 
    o.o_orderdate >= DATE '2023-01-01' AND o.o_orderdate <= DATE '2023-12-31'
GROUP BY 
    p.p_name
ORDER BY 
    total_revenue DESC
LIMIT 10;
