SELECT 
    s.s_name AS supplier_name,
    COUNT(DISTINCT o.o_orderkey) AS total_orders,
    SUM(l.l_extendedprice * (1 - l.l_discount)) AS total_revenue,
    AVG(p.p_retailprice) AS avg_part_price,
    GROUP_CONCAT(DISTINCT p.p_name ORDER BY p.p_name SEPARATOR ', ') AS part_names,
    r.r_name AS region_name
FROM 
    supplier s 
JOIN 
    partsupp ps ON s.s_suppkey = ps.ps_suppkey 
JOIN 
    part p ON ps.ps_partkey = p.p_partkey 
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
    r.r_name LIKE 'N%' 
    AND o.o_orderdate BETWEEN '2023-01-01' AND '2023-12-31' 
GROUP BY 
    s.s_suppkey, r.r_name 
HAVING 
    total_orders > 10
ORDER BY 
    total_revenue DESC;
