SELECT 
    n.n_name, 
    SUM(o.o_totalprice) AS total_revenue 
FROM 
    nation n 
JOIN 
    supplier s ON n.n_nationkey = s.s_nationkey 
JOIN 
    partsupp ps ON s.s_suppkey = ps.ps_suppkey 
JOIN 
    part p ON ps.ps_partkey = p.p_partkey 
JOIN 
    lineitem l ON p.p_partkey = l.l_partkey 
JOIN 
    orders o ON l.l_orderkey = o.o_orderkey 
GROUP BY 
    n.n_name 
ORDER BY 
    total_revenue DESC;
