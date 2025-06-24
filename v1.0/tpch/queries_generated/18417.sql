SELECT
    p.p_name,
    SUM(l.l_extendedprice * (1 - l.l_discount)) AS revenue
FROM
    part p
JOIN
    lineitem l ON p.p_partkey = l.l_partkey
JOIN
    supplier s ON l.l_suppkey = s.s_suppkey
JOIN
    nation n ON s.s_nationkey = n.n_nationkey
WHERE
    n.n_name = 'CANADA'
    AND l.l_shipdate >= DATE '2023-01-01'
    AND l.l_shipdate < DATE '2023-12-31'
GROUP BY
    p.p_name
ORDER BY
    revenue DESC
LIMIT 10;
