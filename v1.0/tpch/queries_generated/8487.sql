SELECT 
    n.n_name AS nation,
    SUM(o.o_totalprice) AS total_revenue,
    COUNT(DISTINCT c.c_custkey) AS customer_count,
    COUNT(DISTINCT o.o_orderkey) AS order_count,
    AVG(l.l_quantity) AS avg_line_quantity,
    STDEV(l.l_quantity) AS stddev_line_quantity
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
JOIN 
    customer c ON o.o_custkey = c.c_custkey
WHERE 
    o.o_orderdate >= '2023-01-01' AND o.o_orderdate < '2023-12-31'
    AND l.l_discount > 0.05
GROUP BY 
    n.n_name
ORDER BY 
    total_revenue DESC
LIMIT 10;
