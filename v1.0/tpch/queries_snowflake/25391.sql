
WITH StringAggregation AS (
    SELECT 
        s.s_name AS supplier_name,
        s.s_address AS supplier_address,
        LISTAGG(p.p_name, ', ') WITHIN GROUP (ORDER BY p.p_name) AS part_names,
        COUNT(DISTINCT p.p_partkey) AS part_count,
        LISTAGG(DISTINCT LEFT(p.p_comment, 20), '; ') WITHIN GROUP (ORDER BY p.p_comment) AS short_comments
    FROM 
        supplier s
    JOIN 
        partsupp ps ON s.s_suppkey = ps.ps_suppkey
    JOIN 
        part p ON ps.ps_partkey = p.p_partkey
    GROUP BY 
        s.s_name, s.s_address
),
RegionSupplier AS (
    SELECT 
        r.r_name AS region_name,
        LISTAGG(DISTINCT sa.supplier_name, '; ') WITHIN GROUP (ORDER BY sa.supplier_name) AS suppliers,
        SUM(sa.part_count) AS total_parts
    FROM 
        region r
    JOIN 
        nation n ON r.r_regionkey = n.n_regionkey
    JOIN 
        supplier s ON n.n_nationkey = s.s_nationkey
    JOIN 
        StringAggregation sa ON sa.supplier_name = s.s_name
    GROUP BY 
        r.r_name
)
SELECT 
    region_name,
    suppliers,
    total_parts
FROM 
    RegionSupplier
WHERE 
    total_parts > 10
ORDER BY 
    region_name;
