WITH RevenueCTE AS (
    SELECT 
        s.s_suppkey,
        s.s_name,
        n.n_name AS nation,
        r.r_name AS region,
        SUM(l.l_extendedprice * (1 - l.l_discount)) AS total_revenue
    FROM 
        supplier s
    JOIN 
        partsupp ps ON s.s_suppkey = ps.ps_suppkey
    JOIN 
        part p ON ps.ps_partkey = p.p_partkey
    JOIN 
        lineitem l ON p.p_partkey = l.l_partkey
    JOIN 
        orders o ON l.l_orderkey = o.o_orderkey
    JOIN 
        nation n ON s.s_nationkey = n.n_nationkey
    JOIN 
        region r ON n.n_regionkey = r.r_regionkey
    WHERE 
        o.o_orderdate >= DATE '2023-01-01' AND o.o_orderdate < DATE '2024-01-01'
    GROUP BY 
        s.s_suppkey, s.s_name, n.n_name, r.r_name
),
RankedRevenue AS (
    SELECT 
        *,
        RANK() OVER (PARTITION BY region ORDER BY total_revenue DESC) AS revenue_rank
    FROM 
        RevenueCTE
)
SELECT 
    r.s_name,
    r.nation,
    r.region,
    r.total_revenue
FROM 
    RankedRevenue r
WHERE 
    r.revenue_rank <= 5
ORDER BY 
    r.region, r.total_revenue DESC;
