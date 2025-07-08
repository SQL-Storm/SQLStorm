WITH RegionalSales AS (
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
        o.o_orderdate >= DATE '1997-01-01' AND o.o_orderdate < DATE '1997-12-31'
    GROUP BY 
        r.r_name
),
TopRegions AS (
    SELECT 
        region_name,
        total_sales,
        RANK() OVER (ORDER BY total_sales DESC) AS sales_rank
    FROM 
        RegionalSales
)
SELECT 
    tr.region_name,
    tr.total_sales,
    tr.sales_rank,
    COUNT(DISTINCT s.s_suppkey) AS supplier_count
FROM 
    TopRegions tr
JOIN 
    nation n ON tr.region_name = (SELECT r.r_name FROM region r WHERE r.r_regionkey = n.n_regionkey)
JOIN 
    supplier s ON n.n_nationkey = s.s_nationkey
WHERE 
    tr.sales_rank <= 10
GROUP BY 
    tr.region_name, tr.total_sales, tr.sales_rank
ORDER BY 
    tr.sales_rank;