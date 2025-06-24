SELECT 
    n_name AS nation, 
    r_name AS region, 
    SUM(l_extendedprice * (1 - l_discount)) AS total_revenue
FROM 
    lineitem 
JOIN 
    orders ON l_orderkey = o_orderkey 
JOIN 
    customer ON o_custkey = c_custkey 
JOIN 
    supplier ON l_suppkey = s_suppkey 
JOIN 
    partsupp ON l_partkey = ps_partkey AND s_suppkey = ps_suppkey 
JOIN 
    part ON l_partkey = p_partkey 
JOIN 
    nation ON c_nationkey = n_nationkey 
JOIN 
    region ON n_regionkey = r_regionkey 
WHERE 
    o_orderdate >= DATE '2023-01-01' 
    AND o_orderdate < DATE '2024-01-01' 
GROUP BY 
    n_name, r_name 
ORDER BY 
    total_revenue DESC;
