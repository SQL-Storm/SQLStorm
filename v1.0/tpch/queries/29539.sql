
SELECT 
    s.s_name AS supplier_name,
    p.p_name AS part_name,
    SUM(ps.ps_availqty) AS total_available_quantity,
    AVG(p.p_retailprice) AS average_retail_price,
    COUNT(DISTINCT o.o_orderkey) AS total_orders,
    STRING_AGG(DISTINCT c.c_name, ', ' ORDER BY c.c_name) AS customers_list,
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
    p.p_name LIKE '%widget%'
    AND s.s_comment NOT LIKE '%cheap%'
GROUP BY 
    s.s_name, p.p_name, r.r_name
HAVING 
    SUM(ps.ps_availqty) > 100
ORDER BY 
    total_orders DESC, average_retail_price DESC;
