WITH RankedParts AS (
    SELECT 
        p.p_partkey, 
        p.p_name, 
        p.p_brand, 
        SUM(ps.ps_availqty) AS total_available_qty, 
        AVG(ps.ps_supplycost) AS avg_supply_cost,
        RANK() OVER (PARTITION BY p.p_brand ORDER BY SUM(ps.ps_availqty) DESC) AS rnk
    FROM 
        part p
    JOIN 
        partsupp ps ON p.p_partkey = ps.ps_partkey
    GROUP BY 
        p.p_partkey, p.p_name, p.p_brand
), CustomerOrders AS (
    SELECT 
        c.c_custkey, 
        c.c_name, 
        COUNT(o.o_orderkey) AS total_orders, 
        SUM(o.o_totalprice) AS total_spent
    FROM 
        customer c
    JOIN 
        orders o ON c.c_custkey = o.o_custkey
    GROUP BY 
        c.c_custkey, c.c_name
), TopRegions AS (
    SELECT 
        r.r_regionkey, 
        r.r_name, 
        COUNT(n.n_nationkey) AS nation_count
    FROM 
        region r
    JOIN 
        nation n ON r.r_regionkey = n.n_regionkey
    GROUP BY 
        r.r_regionkey, r.r_name
    HAVING 
        COUNT(n.n_nationkey) > 5
)
SELECT 
    rp.p_name, 
    rp.total_available_qty, 
    rp.avg_supply_cost, 
    co.total_orders, 
    co.total_spent, 
    tr.r_name AS region_name
FROM 
    RankedParts rp
JOIN 
    CustomerOrders co ON co.total_orders > 10
JOIN 
    TopRegions tr ON co.c_custkey IN (SELECT c.c_custkey FROM customer c WHERE c.c_nationkey IN (SELECT n.n_nationkey FROM nation n WHERE n.n_regionkey = tr.r_regionkey))
WHERE 
    rp.rnk <= 5
ORDER BY 
    rp.total_available_qty DESC, 
    co.total_spent DESC;
