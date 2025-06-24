SELECT 
    l.l_orderkey,
    SUM(l.l_extendedprice * (1 - l.l_discount)) AS total_revenue
FROM 
    lineitem l
JOIN 
    orders o ON l.l_orderkey = o.o_orderkey
JOIN 
    customer c ON o.o_custkey = c.c_custkey
JOIN 
    supplier s ON l.l_suppkey = s.s_suppkey
JOIN 
    partsupp ps ON l.l_partkey = ps.ps_partkey AND s.s_suppkey = ps.ps_suppkey
JOIN 
    part p ON ps.ps_partkey = p.p_partkey
WHERE 
    c.c_mktsegment = 'BUILDING'
    AND l.l_shipdate >= DATE '2021-01-01'
    AND l.l_shipdate < DATE '2022-01-01'
GROUP BY 
    l.l_orderkey
ORDER BY 
    total_revenue DESC
LIMIT 10;
