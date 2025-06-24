SELECT 
    p.p_partkey, 
    SUM(l.l_extendedprice * (1 - l.l_discount)) AS revenue
FROM 
    part p
JOIN 
    lineitem l ON p.p_partkey = l.l_partkey
WHERE 
    l.l_shipdate >= DATE '2022-01-01' 
    AND l.l_shipdate < DATE '2023-01-01'
GROUP BY 
    p.p_partkey
ORDER BY 
    revenue DESC
LIMIT 10;
