SELECT 
    p.p_name, 
    s.s_name, 
    ps.ps_availqty 
FROM 
    part p
JOIN 
    partsupp ps ON p.p_partkey = ps.ps_partkey
JOIN 
    supplier s ON ps.ps_suppkey = s.s_suppkey
WHERE 
    ps.ps_supplycost < 100
ORDER BY 
    ps.ps_availqty DESC
LIMIT 10;
