SELECT 
    n.n_name AS nation_name,
    r.r_name AS region_name,
    SUM(lp.l_extendedprice * (1 - lp.l_discount)) AS total_revenue
FROM 
    lineitem lp
JOIN 
    orders o ON lp.l_orderkey = o.o_orderkey
JOIN 
    customer c ON o.o_custkey = c.c_custkey
JOIN 
    supplier s ON lp.l_suppkey = s.s_suppkey
JOIN 
    nation n ON s.s_nationkey = n.n_nationkey
JOIN 
    region r ON n.n_regionkey = r.r_regionkey
WHERE 
    o.o_orderdate >= DATE '2022-01-01'
    AND o.o_orderdate < DATE '2023-01-01'
GROUP BY 
    n.n_name, r.r_name
ORDER BY 
    total_revenue DESC;
