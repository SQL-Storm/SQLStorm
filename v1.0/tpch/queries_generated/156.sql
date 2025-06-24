WITH CustomerOrders AS (
    SELECT
        c.c_custkey,
        c.c_name,
        SUM(o.o_totalprice) AS total_spent
    FROM
        customer c
    JOIN
        orders o ON c.c_custkey = o.o_custkey
    GROUP BY
        c.c_custkey, c.c_name
),
SupplierParts AS (
    SELECT
        s.s_suppkey,
        s.s_name,
        p.p_partkey,
        p.p_name,
        ps.ps_availqty,
        ps.ps_supplycost
    FROM
        supplier s
    JOIN
        partsupp ps ON s.s_suppkey = ps.ps_suppkey
    JOIN
        part p ON ps.ps_partkey = p.p_partkey
),
OrderDetails AS (
    SELECT
        o.o_orderkey,
        l.l_partkey,
        l.l_suppkey,
        l.l_quantity,
        l.l_extendedprice,
        l.l_discount,
        ROW_NUMBER() OVER (PARTITION BY o.o_orderkey ORDER BY l.l_linenumber) AS line_item_rank
    FROM
        orders o
    JOIN
        lineitem l ON o.o_orderkey = l.l_orderkey
    WHERE
        o.o_orderdate >= '2023-01-01' AND o.o_orderdate < '2024-01-01'
)
SELECT
    c.c_name,
    coalesce(SUM(od.l_extendedprice * (1 - od.l_discount)), 0) AS total_order_value,
    COUNT(DISTINCT od.o_orderkey) AS order_count,
    AVG(sp.ps_supplycost) AS average_supply_cost,
    CASE
        WHEN SUM(od.l_extendedprice * (1 - od.l_discount)) > 1000 THEN 'High Value Customer'
        WHEN SUM(od.l_extendedprice * (1 - od.l_discount)) BETWEEN 500 AND 1000 THEN 'Medium Value Customer'
        ELSE 'Low Value Customer'
    END AS customer_value_category
FROM
    CustomerOrders co
LEFT JOIN
    OrderDetails od ON co.c_custkey = od.o_orderkey
LEFT JOIN
    SupplierParts sp ON od.l_suppkey = sp.s_suppkey
WHERE
    sp.ps_availqty IS NOT NULL
GROUP BY
    c.c_name
ORDER BY
    total_order_value DESC;

WITH RankedRegions AS (
    SELECT
        r.r_name,
        DENSE_RANK() OVER (ORDER BY r.r_regionkey) AS region_rank
    FROM
        region r
),
TopRegions AS (
    SELECT
        rr.r_name
    FROM
        RankedRegions rr
    WHERE
        rr.region_rank <= 5
)
SELECT
    tr.r_name,
    COUNT(DISTINCT s.s_suppkey) AS supplier_count,
    SUM(sp.ps_supplycost) AS total_supply_cost
FROM
    TopRegions tr
JOIN
    nation n ON n.n_regionkey = tr.r_regionkey
JOIN
    supplier s ON n.n_nationkey = s.s_nationkey
JOIN
    partsupp sp ON s.s_suppkey = sp.ps_suppkey
GROUP BY
    tr.r_name
HAVING
    supplier_count > 0
ORDER BY
    total_supply_cost DESC;
