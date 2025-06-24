SELECT 
    p.p_name, 
    SUM(l.l_extendedprice * (1 - l.l_discount)) AS total_revenue
FROM 
    part p
JOIN 
    lineitem l ON p.p_partkey = l.l_partkey
JOIN 
    supplier s ON l.l_suppkey = s.s_suppkey
JOIN 
    partsupp ps ON p.p_partkey = ps.ps_partkey AND s.s_suppkey = ps.ps_suppkey
JOIN 
    orders o ON l.l_orderkey = o.o_orderkey
WHERE 
    o.o_orderdate >= DATE '2023-01-01' AND o.o_orderdate < DATE '2023-02-01'
GROUP BY 
    p.p_name
ORDER BY 
    total_revenue DESC
LIMIT 10;
