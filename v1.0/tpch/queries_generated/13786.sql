SELECT 
    l.l_shipmode, 
    SUM(l.l_extendedprice * (1 - l.l_discount)) AS revenue
FROM 
    lineitem l
JOIN 
    orders o ON l.l_orderkey = o.o_orderkey
WHERE 
    o.o_orderdate >= '2023-01-01' AND o.o_orderdate < '2023-12-31'
GROUP BY 
    l.l_shipmode
ORDER BY 
    revenue DESC;
