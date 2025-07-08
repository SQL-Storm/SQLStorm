
SELECT 
    p.p_name, 
    s.s_name, 
    n.n_name, 
    CONCAT('Supplier: ', s.s_name, ', Part: ', p.p_name) AS supplier_part_info,
    REPLACE(p.p_comment, 'old', 'new') AS updated_comment,
    LENGTH(p.p_name) AS part_name_length,
    LENGTH(s.s_name) AS supplier_name_length 
FROM 
    part p
JOIN 
    partsupp ps ON p.p_partkey = ps.ps_partkey
JOIN 
    supplier s ON ps.ps_suppkey = s.s_suppkey
JOIN 
    nation n ON s.s_nationkey = n.n_nationkey
WHERE 
    s.s_acctbal > 1000.00 
AND 
    p.p_size BETWEEN 10 AND 50
GROUP BY 
    p.p_name, 
    s.s_name, 
    n.n_name, 
    REPLACE(p.p_comment, 'old', 'new'), 
    LENGTH(p.p_name), 
    LENGTH(s.s_name)
ORDER BY 
    LENGTH(p.p_name) DESC, 
    LENGTH(s.s_name) ASC
LIMIT 10;
