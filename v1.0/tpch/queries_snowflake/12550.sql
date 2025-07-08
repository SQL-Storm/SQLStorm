SELECT 
    p.p_partkey, 
    p.p_name, 
    s.s_name, 
    ps.ps_availqty, 
    ps.ps_supplycost, 
    SUM(l.l_extendedprice * (1 - l.l_discount)) AS revenue
FROM 
    part p
JOIN 
    partsupp ps ON p.p_partkey = ps.ps_partkey
JOIN 
    supplier s ON ps.ps_suppkey = s.s_suppkey
JOIN 
    lineitem l ON p.p_partkey = l.l_partkey
GROUP BY 
    p.p_partkey, 
    p.p_name, 
    s.s_name, 
    ps.ps_availqty, 
    ps.ps_supplycost
ORDER BY 
    revenue DESC
LIMIT 10;
