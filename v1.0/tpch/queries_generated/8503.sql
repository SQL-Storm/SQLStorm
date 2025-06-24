WITH RevenueByNation AS (
    SELECT n.n_name AS nation, SUM(l.l_extendedprice * (1 - l.l_discount)) AS total_revenue
    FROM nation n
    JOIN supplier s ON n.n_nationkey = s.s_nationkey
    JOIN partsupp ps ON s.s_suppkey = ps.ps_suppkey
    JOIN part p ON ps.ps_partkey = p.p_partkey
    JOIN lineitem l ON p.p_partkey = l.l_partkey
    JOIN orders o ON l.l_orderkey = o.o_orderkey
    GROUP BY n.n_name
),
RankedRevenue AS (
    SELECT nation, total_revenue,
           RANK() OVER (ORDER BY total_revenue DESC) AS revenue_rank
    FROM RevenueByNation
)
SELECT r.nation, r.total_revenue
FROM RankedRevenue r
WHERE r.revenue_rank <= 5
ORDER BY r.total_revenue DESC;
