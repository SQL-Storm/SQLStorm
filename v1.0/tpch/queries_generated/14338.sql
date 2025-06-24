SELECT 
    p.p_brand, 
    p.p_type, 
    SUM(l.l_extendedprice * (1 - l.l_discount)) AS revenue
FROM 
    lineitem l
JOIN 
    partsupp ps ON l.l_partkey = ps.ps_partkey
JOIN 
    part p ON ps.ps_partkey = p.p_partkey
JOIN 
    supplier s ON ps.ps_suppkey = s.s_suppkey
JOIN 
    nation n ON s.s_nationkey = n.n_nationkey
JOIN 
    region r ON n.n_regionkey = r.r_regionkey
WHERE 
    r.r_name = 'ASIA'
    AND l.l_shipdate >= DATE '2021-01-01'
    AND l.l_shipdate < DATE '2021-02-01'
GROUP BY 
    p.p_brand, p.p_type
ORDER BY 
    revenue DESC;
