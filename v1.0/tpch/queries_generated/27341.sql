SELECT 
    p.p_name,
    s.s_name,
    sum(l.l_quantity) AS total_quantity,
    sum(l.l_extendedprice * (1 - l.l_discount)) AS total_revenue,
    avg(l.l_discount) AS avg_discount,
    max(p.p_retailprice) AS highest_price,
    substring(s.s_comment, 1, 20) AS comment_preview
FROM 
    part p
JOIN 
    partsupp ps ON p.p_partkey = ps.ps_partkey
JOIN 
    supplier s ON ps.ps_suppkey = s.s_suppkey
JOIN 
    lineitem l ON l.l_partkey = p.p_partkey
JOIN 
    orders o ON l.l_orderkey = o.o_orderkey
JOIN 
    customer c ON o.o_custkey = c.c_custkey
WHERE 
    c.c_mktsegment = 'BUILDING'
    AND l.l_shipdate BETWEEN '2023-01-01' AND '2023-12-31'
GROUP BY 
    p.p_name, s.s_name
ORDER BY 
    total_revenue DESC
LIMIT 10;
