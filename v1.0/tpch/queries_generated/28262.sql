SELECT 
    p.p_name, 
    CONCAT('Manufacturer: ', p.p_mfgr, ', Brand: ', p.p_brand, ', Type: ', p.p_type) AS product_details,
    s.s_name AS supplier_name,
    CASE 
        WHEN ps_availqty < 50 THEN 'Low stock' 
        WHEN ps_availqty BETWEEN 50 AND 100 THEN 'Moderate stock' 
        ELSE 'High stock' 
    END AS stock_status,
    CONCAT(ROUND(ps_supplycost::numeric, 2), ' USD') AS supply_cost_formatted,
    r.r_name AS region_name,
    n.n_name AS nation_name
FROM 
    part p
JOIN 
    partsupp ps ON p.p_partkey = ps.ps_partkey
JOIN 
    supplier s ON ps.ps_suppkey = s.s_suppkey
JOIN 
    nation n ON s.s_nationkey = n.n_nationkey
JOIN 
    region r ON n.n_regionkey = r.r_regionkey
WHERE 
    p.p_retailprice > (SELECT AVG(p_retailprice) FROM part)
ORDER BY 
    p.p_name ASC, 
    s.s_name DESC;
