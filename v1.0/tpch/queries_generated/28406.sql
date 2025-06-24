SELECT 
    p.p_name AS part_name, 
    COUNT(DISTINCT s.s_suppkey) AS supplier_count,
    MAX(ps.ps_supplycost) AS max_supply_cost,
    SUM(l.l_quantity) AS total_quantity,
    AVG(l.l_extendedprice) AS avg_extended_price,
    STRING_AGG(DISTINCT c.c_name, ', ') AS customer_names,
    r.r_name AS region_name
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
    p.p_name LIKE '%steel%'
    AND o.o_orderdate BETWEEN '2022-01-01' AND '2023-01-01'
GROUP BY 
    p.p_name, r.r_name
HAVING 
    SUM(l.l_quantity) > 1000
ORDER BY 
    total_quantity DESC;
