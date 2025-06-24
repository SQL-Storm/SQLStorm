SELECT 
    n_name, 
    SUM(l_extendedprice * (1 - l_discount)) AS revenue
FROM 
    lineitem 
JOIN 
    orders ON l_orderkey = o_orderkey 
JOIN 
    customer ON o_custkey = c_custkey 
JOIN 
    supplier ON l_suppkey = s_suppkey 
JOIN 
    nation ON s_nationkey = n_nationkey 
WHERE 
    l_shipdate >= DATE '2023-01-01' 
    AND l_shipdate < DATE '2024-01-01' 
GROUP BY 
    n_name 
ORDER BY 
    revenue DESC;
