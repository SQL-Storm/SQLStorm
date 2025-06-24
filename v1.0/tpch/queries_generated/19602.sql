SELECT 
    p_pkey, 
    p_name, 
    SUM(l_quantity) AS total_quantity
FROM 
    part p
JOIN 
    lineitem l ON p.p_partkey = l.l_partkey
GROUP BY 
    p.p_partkey, p.p_name
ORDER BY 
    total_quantity DESC
LIMIT 10;
