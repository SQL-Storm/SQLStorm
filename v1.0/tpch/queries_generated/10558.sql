SELECT
    n.n_name,
    SUM(l.l_extendedprice * (1 - l.l_discount)) AS total_revenue
FROM
    nation n
JOIN
    supplier s ON n.n_nationkey = s.s_nationkey
JOIN
    partsupp ps ON s.s_suppkey = ps.ps_suppkey
JOIN
    part p ON ps.ps_partkey = p.p_partkey
JOIN
    lineitem l ON p.p_partkey = l.l_partkey
WHERE
    l.l_shipdate >= DATE '2023-01-01' AND l.l_shipdate < DATE '2023-02-01'
GROUP BY
    n.n_nationkey, n.n_name
ORDER BY
    total_revenue DESC;
