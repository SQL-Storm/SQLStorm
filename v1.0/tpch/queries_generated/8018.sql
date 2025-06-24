WITH RegionStats AS (
    SELECT r.r_name AS region_name, 
           SUM(o.o_totalprice) AS total_revenue, 
           COUNT(DISTINCT c.c_custkey) AS customer_count
    FROM region r
    JOIN nation n ON r.r_regionkey = n.n_regionkey
    JOIN supplier s ON n.n_nationkey = s.s_nationkey
    JOIN partsupp ps ON s.s_suppkey = ps.ps_suppkey
    JOIN part p ON ps.ps_partkey = p.p_partkey
    JOIN lineitem l ON p.p_partkey = l.l_partkey
    JOIN orders o ON l.l_orderkey = o.o_orderkey
    JOIN customer c ON o.o_custkey = c.c_custkey
    WHERE l.l_shipdate >= DATE '2023-01-01' AND l.l_shipdate < DATE '2023-10-01'
    GROUP BY r.r_name
), 
TopRegions AS (
    SELECT region_name, 
           total_revenue, 
           customer_count,
           RANK() OVER (ORDER BY total_revenue DESC) AS revenue_rank
    FROM RegionStats
)
SELECT region_name, 
       total_revenue, 
       customer_count
FROM TopRegions
WHERE revenue_rank <= 5
ORDER BY total_revenue DESC;
