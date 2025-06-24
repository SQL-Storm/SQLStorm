EXPLAIN ANALYZE
SELECT 
    n.n_name, 
    SUM(l.l_extendedprice * (1 - l.l_discount)) AS revenue
FROM 
    part p
JOIN 
    lineitem l ON p.p_partkey = l.l_partkey
JOIN 
    supplier s ON l.l_suppkey = s.s_suppkey
JOIN 
    nation n ON s.s_nationkey = n.n_nationkey
JOIN 
    region r ON n.n_regionkey = r.r_regionkey
WHERE 
    r.r_name = 'ASIA' 
    AND l.l_shipdate >= DATE '2023-01-01' 
    AND l.l_shipdate < DATE '2024-01-01'
GROUP BY 
    n.n_name
ORDER BY 
    revenue DESC;
