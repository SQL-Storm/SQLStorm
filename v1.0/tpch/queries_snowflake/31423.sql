
WITH RECURSIVE RegionSales AS (
    SELECT 
        r.r_name AS region_name,
        SUM(l.l_extendedprice * (1 - l.l_discount)) AS total_sales
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
        o.o_orderstatus = 'F' 
        AND l.l_shipdate >= '1997-01-01'
    GROUP BY 
        r.r_name
    UNION ALL
    SELECT 
        RS.region_name,
        SUM(l.l_extendedprice * (1 - l.l_discount)) AS total_sales
    FROM 
        RegionSales RS
    JOIN 
        orders o ON RS.region_name IS NOT NULL
    JOIN 
        lineitem l ON o.o_orderkey = l.l_orderkey
    WHERE 
        l.l_shipdate > DATEADD(year, -1, '1998-10-01')
    GROUP BY 
        RS.region_name
),
RankedSales AS (
    SELECT 
        region_name,
        total_sales,
        ROW_NUMBER() OVER (ORDER BY total_sales DESC) AS sales_rank
    FROM 
        RegionSales
)
SELECT 
    r.r_name AS region_name,
    COALESCE(rs.total_sales, 0) AS total_sales,
    CASE 
        WHEN rs.total_sales IS NULL THEN 'No Sales'
        ELSE 'Sales Made'
    END AS sales_status
FROM 
    region r
LEFT JOIN 
    RankedSales rs ON r.r_name = rs.region_name
ORDER BY 
    sales_rank ASC NULLS LAST;
