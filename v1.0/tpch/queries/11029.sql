
SELECT 
    p.p_name, 
    SUM(l.l_extendedprice * (1 - l.l_discount)) AS revenue 
FROM 
    part p 
JOIN 
    lineitem l ON p.p_partkey = l.l_partkey 
JOIN 
    supplier s ON l.l_suppkey = s.s_suppkey 
JOIN 
    partsupp ps ON p.p_partkey = ps.ps_partkey AND s.s_suppkey = ps.ps_suppkey 
JOIN 
    orders o ON o.o_orderkey = l.l_orderkey 
JOIN 
    customer c ON c.c_custkey = o.o_custkey 
WHERE 
    c.c_mktsegment = 'BUILDING' 
    AND l.l_shipdate >= DATE '1994-01-01' 
    AND l.l_shipdate < DATE '1995-01-01' 
GROUP BY 
    p.p_name 
ORDER BY 
    revenue DESC 
FETCH FIRST 10 ROWS ONLY;
