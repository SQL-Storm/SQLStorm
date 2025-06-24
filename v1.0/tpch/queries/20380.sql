WITH RegionalSales AS (
    SELECT 
        r.r_name AS region_name,
        SUM(l.l_extendedprice * (1 - l.l_discount)) AS total_sales,
        COUNT(DISTINCT o.o_orderkey) AS order_count,
        ROW_NUMBER() OVER (PARTITION BY r.r_name ORDER BY SUM(l.l_extendedprice * (1 - l.l_discount)) DESC) AS sales_rank
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
        lineitem l ON p.p_partkey = l.l_partkey
    JOIN 
        orders o ON l.l_orderkey = o.o_orderkey
    WHERE 
        o.o_orderstatus IN ('F', 'O') 
        AND (o.o_totalprice > 1000 OR l.l_discount < 0.05)
        AND l.l_shipdate IS NOT NULL
    GROUP BY 
        r.r_name
),
TopRegions AS (
    SELECT 
        region_name,
        total_sales,
        order_count
    FROM 
        RegionalSales
    WHERE 
        sales_rank <= 3
)
SELECT 
    t.region_name,
    t.total_sales,
    t.order_count,
    COALESCE((SELECT AVG(total_sales) FROM TopRegions), 0) AS avg_top_sales,
    CASE 
        WHEN t.total_sales > 2 * (SELECT AVG(total_sales) FROM TopRegions) THEN 'High Performer'
        WHEN t.total_sales < (SELECT MIN(total_sales) FROM TopRegions) THEN 'Low Performer'
        ELSE 'Average Performer' 
    END AS performance_category
FROM 
    TopRegions t
ORDER BY 
    t.total_sales DESC
OFFSET 1 ROWS;