SELECT 
    n.n_name, 
    SUM(l.l_extendedprice * (1 - l.l_discount)) AS total_revenue
FROM 
    supplier AS s
JOIN 
    partsupp AS ps ON s.s_suppkey = ps.ps_suppkey
JOIN 
    part AS p ON ps.ps_partkey = p.p_partkey
JOIN 
    lineitem AS l ON p.p_partkey = l.l_partkey
JOIN 
    orders AS o ON l.l_orderkey = o.o_orderkey
JOIN 
    customer AS c ON o.o_custkey = c.c_custkey
JOIN 
    nation AS n ON s.s_nationkey = n.n_nationkey
WHERE 
    o.o_orderdate >= DATE '2022-01-01' AND o.o_orderdate < DATE '2023-01-01'
GROUP BY 
    n.n_name
ORDER BY 
    total_revenue DESC
LIMIT 10;
