SELECT 
    SUM(l_extendedprice * (1 - l_discount)) AS total_revenue,
    o_orderdate
FROM 
    lineitem
JOIN 
    orders ON l_orderkey = o_orderkey
WHERE 
    o_orderdate >= '2022-01-01' AND o_orderdate < '2023-01-01'
GROUP BY 
    o_orderdate
ORDER BY 
    o_orderdate;
