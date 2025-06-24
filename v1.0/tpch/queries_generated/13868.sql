SELECT 
    p.p_name,
    SUM(l.l_extendedprice * (1 - l.l_discount)) AS total_revenue
FROM 
    part p
JOIN 
    lineitem l ON p.p_partkey = l.l_partkey
JOIN 
    partsupp ps ON p.p_partkey = ps.ps_partkey
JOIN 
    supplier s ON ps.ps_suppkey = s.s_suppkey
JOIN 
    customer c ON c.c_custkey = l.l_orderkey
JOIN 
    orders o ON c.c_custkey = o.o_custkey
WHERE 
    o.o_orderdate >= '2022-01-01' AND o.o_orderdate < '2023-01-01'
GROUP BY 
    p.p_name
ORDER BY 
    total_revenue DESC
LIMIT 10;
