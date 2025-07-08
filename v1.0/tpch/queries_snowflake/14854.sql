SELECT 
    s.s_name, 
    SUM(ps.ps_supplycost * ps.ps_availqty) AS total_supply_cost
FROM 
    supplier s
JOIN 
    partsupp ps ON s.s_suppkey = ps.ps_suppkey
JOIN 
    part p ON ps.ps_partkey = p.p_partkey
GROUP BY 
    s.s_name
ORDER BY 
    total_supply_cost DESC
LIMIT 10;
