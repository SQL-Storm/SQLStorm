SELECT 
    n.n_name AS nation,
    SUM(l.l_extendedprice * (1 - l.l_discount)) AS total_revenue
FROM 
    lineitem l 
JOIN 
    orders o ON l.l_orderkey = o.o_orderkey
JOIN 
    customer c ON o.o_custkey = c.c_custkey
JOIN 
    nation n ON c.c_nationkey = n.n_nationkey
WHERE 
    o.o_orderdate >= '2023-01-01'
    AND o.o_orderdate < '2023-12-31'
GROUP BY 
    n.n_name
ORDER BY 
    total_revenue DESC;
