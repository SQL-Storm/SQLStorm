WITH RECURSIVE order_hierarchy AS (
    SELECT o.o_orderkey, o.o_orderdate, o.o_totalprice, c.c_name,
           ROW_NUMBER() OVER (PARTITION BY c.c_nationkey ORDER BY o.o_orderdate DESC) AS rn
    FROM orders o
    JOIN customer c ON o.o_custkey = c.c_custkey
    WHERE o.o_orderstatus = 'O'
),
supplier_summary AS (
    SELECT s.s_suppkey, s.s_name, SUM(ps.ps_supplycost) AS total_supplycost
    FROM supplier s
    JOIN partsupp ps ON s.s_suppkey = ps.ps_suppkey
    GROUP BY s.s_suppkey, s.s_name
),
part_pricing AS (
    SELECT p.p_partkey, p.p_name, AVG(ps.ps_supplycost) AS avg_supplycost,
           COUNT(ps.ps_partkey) AS total_suppliers
    FROM part p
    JOIN partsupp ps ON p.p_partkey = ps.ps_partkey
    WHERE p.p_retailprice > 100.00
    GROUP BY p.p_partkey, p.p_name
),
customer_order_stats AS (
    SELECT c.c_custkey, COUNT(o.o_orderkey) AS order_count,
           SUM(o.o_totalprice) AS total_order_value
    FROM customer c
    JOIN orders o ON c.c_custkey = o.o_custkey
    GROUP BY c.c_custkey
)
SELECT oh.o_orderkey, oh.o_orderdate, oh.c_name, 
       ps.p_name, pp.avg_supplycost, s.s_name,
       cs.order_count, cs.total_order_value
FROM order_hierarchy oh
LEFT JOIN lineitem li ON oh.o_orderkey = li.l_orderkey
LEFT JOIN part_pricing pp ON li.l_partkey = pp.p_partkey
LEFT JOIN supplier_summary s ON pp.total_suppliers > 10 AND s.total_supplycost < 5000
LEFT JOIN customer_order_stats cs ON oh.c_name = (SELECT c.c_name 
                                                    FROM customer c 
                                                    WHERE c.c_custkey = oh.o_orderkey 
                                                    LIMIT 1)
WHERE oh.rn = 1
ORDER BY oh.o_orderdate DESC, pp.avg_supplycost DESC;
