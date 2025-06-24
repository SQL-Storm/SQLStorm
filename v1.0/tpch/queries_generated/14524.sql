SELECT
    p.p_partkey,
    p.p_name,
    SUM(l.l_quantity) AS total_quantity,
    AVG(l.l_extendedprice) AS avg_price,
    COUNT(DISTINCT o.o_orderkey) AS total_orders
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
WHERE
    o.o_orderdate BETWEEN '2021-01-01' AND '2021-12-31'
GROUP BY
    p.p_partkey, p.p_name
ORDER BY
    total_quantity DESC
LIMIT 100;
