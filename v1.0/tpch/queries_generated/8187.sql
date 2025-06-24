WITH regional_summary AS (
    SELECT r.r_name AS region_name,
           SUM(l.l_extendedprice * (1 - l.l_discount)) AS total_revenue,
           COUNT(DISTINCT o.o_orderkey) AS total_orders,
           COUNT(DISTINCT c.c_custkey) AS unique_customers
    FROM region r
    JOIN nation n ON r.r_regionkey = n.n_regionkey
    JOIN supplier s ON n.n_nationkey = s.s_nationkey
    JOIN partsupp ps ON s.s_suppkey = ps.ps_suppkey
    JOIN part p ON ps.ps_partkey = p.p_partkey
    JOIN lineitem l ON p.p_partkey = l.l_partkey
    JOIN orders o ON l.l_orderkey = o.o_orderkey
    JOIN customer c ON o.o_custkey = c.c_custkey
    WHERE o.o_orderdate >= date '2022-01-01'
      AND o.o_orderdate < date '2023-01-01'
    GROUP BY r.r_name
)
SELECT region_name,
       total_revenue,
       total_orders,
       unique_customers,
       RANK() OVER (ORDER BY total_revenue DESC) AS revenue_rank
FROM regional_summary
WHERE total_revenue > 100000
ORDER BY revenue_rank;
