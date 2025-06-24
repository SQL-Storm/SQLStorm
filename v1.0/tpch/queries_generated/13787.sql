SELECT 
    p.p_name, 
    SUM(l.l_quantity) AS total_quantity, 
    SUM(l.l_extendedprice) AS total_revenue, 
    AVG(l.l_discount) AS avg_discount
FROM 
    part p 
JOIN 
    lineitem l ON p.p_partkey = l.l_partkey
JOIN 
    partsupp ps ON p.p_partkey = ps.ps_partkey
JOIN 
    supplier s ON ps.ps_suppkey = s.s_suppkey
JOIN 
    nation n ON s.s_nationkey = n.n_nationkey
JOIN 
    region r ON n.n_regionkey = r.r_regionkey
WHERE 
    r.r_name = 'Europe' 
    AND l.l_shipdate >= '2023-01-01' 
    AND l.l_shipdate < '2024-01-01'
GROUP BY 
    p.p_name
ORDER BY 
    total_revenue DESC
LIMIT 10;
