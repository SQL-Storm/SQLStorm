SELECT 
    CONCAT(s.s_name, ' from ', c.c_name) AS supplier_customer,
    COUNT(DISTINCT o.o_orderkey) AS total_orders,
    SUM(l.l_extendedprice * (1 - l.l_discount)) AS total_revenue,
    AVG(p.p_retailprice) AS average_part_price,
    STRING_AGG(DISTINCT p.p_name, ', ') AS part_names
FROM 
    supplier s
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
    s.s_acctbal > 1000.00 
    AND l.l_returnflag = 'N'
GROUP BY 
    supplier_customer
HAVING 
    SUM(l.l_extendedprice * (1 - l.l_discount)) > 50000.00
ORDER BY 
    total_revenue DESC;
