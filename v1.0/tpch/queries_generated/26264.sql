SELECT 
    p.p_name AS part_name, 
    s.s_name AS supplier_name, 
    c.c_name AS customer_name, 
    COUNT(DISTINCT o.o_orderkey) AS total_orders,
    SUM(l.l_extendedprice * (1 - l.l_discount)) AS total_revenue,
    SUBSTRING_INDEX(GROUP_CONCAT(DISTINCT l.l_comment ORDER BY l.l_comment SEPARATOR '; '), '; ', 5) AS sample_comments
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
WHERE 
    p.p_name LIKE 'rubber%' 
    AND o.o_orderdate BETWEEN '2023-10-01' AND '2023-10-31'
GROUP BY 
    p.p_name, s.s_name, c.c_name
HAVING 
    total_orders > 5
ORDER BY 
    total_revenue DESC;
