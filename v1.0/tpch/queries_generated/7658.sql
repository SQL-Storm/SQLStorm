WITH RegionTotal AS (
    SELECT 
        r.r_regionkey,
        r.r_name,
        SUM(CASE WHEN o.o_orderstatus = 'F' THEN l.l_extendedprice * (1 - l.l_discount) ELSE 0 END) AS total_revenue,
        COUNT(DISTINCT o.o_orderkey) AS order_count
    FROM 
        region r
    JOIN 
        nation n ON r.r_regionkey = n.n_regionkey
    JOIN 
        supplier s ON n.n_nationkey = s.s_nationkey
    JOIN 
        partsupp ps ON s.s_suppkey = ps.ps_suppkey
    JOIN 
        part p ON ps.ps_partkey = p.p_partkey
    JOIN 
        lineitem l ON l.l_partkey = p.p_partkey
    JOIN 
        orders o ON l.l_orderkey = o.o_orderkey
    WHERE 
        o.o_orderdate >= DATE '2023-01-01' AND o.o_orderdate < DATE '2024-01-01'
    GROUP BY 
        r.r_regionkey, r.r_name
),
TopRegions AS (
    SELECT 
        r.*,
        ROW_NUMBER() OVER (ORDER BY rt.total_revenue DESC) AS rank
    FROM 
        region r
    JOIN 
        RegionTotal rt ON r.r_regionkey = rt.r_regionkey
)
SELECT 
    t.r_name,
    t.total_revenue,
    t.order_count
FROM 
    TopRegions t
WHERE 
    t.rank <= 5
ORDER BY 
    t.total_revenue DESC;
