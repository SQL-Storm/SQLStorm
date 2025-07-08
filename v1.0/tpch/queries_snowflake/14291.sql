
SELECT 
    l_returnflag, 
    l_linestatus, 
    SUM(l_quantity) AS sum_quantity, 
    SUM(l_extendedprice) AS sum_extendedprice, 
    SUM(l_extendedprice * (1 - l_discount)) AS sum_discounted_price, 
    SUM(l_extendedprice * (1 - l_discount) * (1 + l_tax)) AS sum_total_price, 
    COUNT(*) AS count_order 
FROM 
    lineitem 
WHERE 
    l_shipdate >= DATE '1998-01-01' AND l_shipdate < DATEADD(YEAR, 1, DATE '1998-01-01') 
GROUP BY 
    l_returnflag, l_linestatus 
ORDER BY 
    l_returnflag, l_linestatus;
