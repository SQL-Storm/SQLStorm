WITH RECURSIVE top_suppliers AS (
    SELECT s.s_suppkey, s.s_name, 
           SUM(ps.ps_supplycost * ps.ps_availqty) AS total_cost
    FROM supplier s
    JOIN partsupp ps ON s.s_suppkey = ps.ps_suppkey
    GROUP BY s.s_suppkey, s.s_name
    HAVING SUM(ps.ps_supplycost * ps.ps_availqty) > 10000
), 
dates AS (
    SELECT o.o_orderdate,
           DENSE_RANK() OVER (ORDER BY o.o_orderdate) AS order_rank
    FROM orders o
    GROUP BY o.o_orderdate
),
lineitem_summary AS (
    SELECT l.l_orderkey,
           SUM(l.l_extendedprice * (1 - l.l_discount)) AS total_revenue,
           MAX(l.l_shipdate) AS last_shipdate
    FROM lineitem l
    WHERE l.l_shipdate >= '2023-01-01' AND l.l_shipdate <= '2023-12-31'
    GROUP BY l.l_orderkey
)
SELECT n.n_name, 
       COALESCE(SUM(ls.total_revenue), 0) AS total_revenue,
       COUNT(DISTINCT o.o_orderkey) AS order_count,
       MAX(s.s_name) AS top_supplier,
       r.r_name
FROM nation n
LEFT JOIN region r ON n.n_regionkey = r.r_regionkey
LEFT JOIN customer c ON n.n_nationkey = c.c_nationkey
LEFT JOIN orders o ON c.c_custkey = o.o_custkey
LEFT JOIN lineitem_summary ls ON o.o_orderkey = ls.l_orderkey
LEFT JOIN top_suppliers s ON s.s_suppkey = (SELECT ps.ps_suppkey
                                              FROM partsupp ps
                                              JOIN lineitem l ON l.l_partkey = ps.ps_partkey
                                              WHERE l.l_orderkey = o.o_orderkey
                                              ORDER BY ps.ps_supplycost * ps.ps_availqty DESC
                                              LIMIT 1)
WHERE o.o_orderdate BETWEEN '2023-01-01' AND '2023-12-31'
GROUP BY n.n_name, r.r_name
HAVING SUM(ls.total_revenue) IS NOT NULL OR COUNT(DISTINCT o.o_orderkey) > 0
ORDER BY total_revenue DESC, order_count DESC;
