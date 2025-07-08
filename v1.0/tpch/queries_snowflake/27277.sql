
SELECT 
    p.p_name AS Part_Name,
    s.s_name AS Supplier_Name,
    c.c_name AS Customer_Name,
    COUNT(DISTINCT o.o_orderkey) AS Total_Orders,
    SUM(l.l_quantity) AS Total_Quantity,
    AVG(p.p_retailprice) AS Avg_Retail_Price,
    LISTAGG(DISTINCT r.r_name, ', ') WITHIN GROUP (ORDER BY r.r_name) AS Regions_Supplied,
    LISTAGG(DISTINCT n.n_name, ', ') WITHIN GROUP (ORDER BY n.n_name) AS Nations_Supplied
FROM 
    part p
JOIN 
    partsupp ps ON p.p_partkey = ps.ps_partkey
JOIN 
    supplier s ON ps.ps_suppkey = s.s_suppkey
JOIN 
    lineitem l ON p.p_partkey = l.l_partkey
JOIN 
    orders o ON l.l_orderkey = o.o_orderkey
JOIN 
    customer c ON o.o_custkey = c.c_custkey
JOIN 
    nation n ON s.s_nationkey = n.n_nationkey
JOIN 
    region r ON n.n_regionkey = r.r_regionkey
WHERE 
    p.p_comment LIKE '%performance%'
    AND o.o_orderdate BETWEEN DATE '1997-01-01' AND DATE '1997-12-31'
GROUP BY 
    p.p_name, s.s_name, c.c_name, p.p_retailprice
ORDER BY 
    Total_Orders DESC, Total_Quantity ASC;
