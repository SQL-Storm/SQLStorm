WITH regional_sales AS (
    SELECT 
        n.n_name AS nation_name, 
        r.r_name AS region_name, 
        SUM(l.l_extendedprice * (1 - l.l_discount)) AS total_sales
    FROM 
        lineitem l
    JOIN 
        orders o ON l.l_orderkey = o.o_orderkey
    JOIN 
        supplier s ON l.l_suppkey = s.s_suppkey
    JOIN 
        nation n ON s.s_nationkey = n.n_nationkey
    JOIN 
        region r ON n.n_regionkey = r.r_regionkey
    WHERE 
        o.o_orderdate >= DATE '2023-01-01' AND o.o_orderdate < DATE '2024-01-01'
    GROUP BY 
        n.n_name, r.r_name
), ranked_sales AS (
    SELECT 
        nation_name, 
        region_name, 
        total_sales, 
        RANK() OVER (PARTITION BY region_name ORDER BY total_sales DESC) AS sales_rank
    FROM 
        regional_sales
)
SELECT 
    nation_name, 
    region_name, 
    total_sales 
FROM 
    ranked_sales 
WHERE 
    sales_rank <= 5 
ORDER BY 
    region_name, total_sales DESC;
