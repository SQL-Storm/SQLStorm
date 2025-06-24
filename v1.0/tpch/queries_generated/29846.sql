SELECT 
    p.p_name, 
    p.p_brand, 
    s.s_name AS supplier_name,
    c.c_name AS customer_name, 
    r.r_name AS region,
    SUM(l.l_quantity) AS total_quantity,
    AVG(l.l_extendedprice) AS average_extended_price,
    COUNT(DISTINCT o.o_orderkey) AS order_count,
    STRING_AGG(DISTINCT SUBSTRING(p.p_comment, 1, 10), ', ') AS short_comments
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
    p.p_brand LIKE '%BrandA%' 
    AND o.o_orderdate >= DATE '2023-01-01' 
    AND o.o_orderdate < DATE '2024-01-01' 
GROUP BY 
    p.p_name, p.p_brand, s.s_name, c.c_name, r.r_name
ORDER BY 
    total_quantity DESC, average_extended_price DESC
LIMIT 10;
