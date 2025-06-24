SELECT 
    n_name, 
    SUM(l_extendedprice * (1 - l_discount)) AS total_revenue
FROM 
    customer 
JOIN 
    orders ON c_custkey = o_custkey 
JOIN 
    lineitem ON o_orderkey = l_orderkey 
JOIN 
    supplier ON l_suppkey = s_suppkey 
JOIN 
    partsupp ON l_partkey = ps_partkey AND s_suppkey = ps_suppkey 
JOIN 
    part ON ps_partkey = p_partkey 
JOIN 
    nation ON s_nationkey = n_nationkey 
WHERE 
    o_orderdate >= DATE '2023-01-01' AND o_orderdate < DATE '2023-12-31' 
GROUP BY 
    n_name 
ORDER BY 
    total_revenue DESC
LIMIT 10;
