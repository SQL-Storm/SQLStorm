SELECT 
    SUBSTRING(p_name, 1, 10) AS short_name,
    CONCAT(a.n_name, ' - ', b.r_name) AS location_info,
    SUM(ps_supplycost * ps_availqty) AS total_supply_cost
FROM 
    part p
JOIN 
    partsupp ps ON p.p_partkey = ps.ps_partkey
JOIN 
    supplier s ON ps.ps_suppkey = s.s_suppkey
JOIN 
    nation a ON s.s_nationkey = a.n_nationkey
JOIN 
    region b ON a.n_regionkey = b.r_regionkey
WHERE 
    LENGTH(p.p_comment) > 15
GROUP BY 
    short_name, location_info
HAVING 
    total_supply_cost > 10000
ORDER BY 
    total_supply_cost DESC, short_name ASC;
