SELECT 
    p.p_name,
    s.s_name,
    COUNT(DISTINCT c.c_custkey) AS unique_customers,
    SUM(l.l_quantity) AS total_quantity,
    AVG(l.l_extendedprice) AS avg_price,
    STRING_AGG(DISTINCT r.r_name, ', ') AS regions_supplied
FROM 
    part p
JOIN 
    partsupp ps ON p.p_partkey = ps.ps_partkey
JOIN 
    supplier s ON ps.ps_suppkey = s.s_suppkey
JOIN 
    lineitem l ON p.p_partkey = l.l_partkey
JOIN 
    orders o ON l.l_orderkey = o.o_orderkey
JOIN 
    customer c ON o.o_custkey = c.c_custkey
JOIN 
    nation n ON s.s_nationkey = n.n_nationkey
JOIN 
    region r ON n.n_regionkey = r.r_regionkey
WHERE 
    l.l_shipdate BETWEEN '2022-01-01' AND '2022-12-31'
AND 
    p.p_type LIKE '%brass%'
GROUP BY 
    p.p_name, s.s_name
HAVING 
    SUM(l.l_discount) > 0.05
ORDER BY 
    total_quantity DESC;
