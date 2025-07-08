
WITH RankedSuppliers AS (
    SELECT 
        s.s_name,
        n.n_name AS nation,
        SUM(ps.ps_supplycost * ps.ps_availqty) AS total_cost,
        ROW_NUMBER() OVER (PARTITION BY n.n_name ORDER BY SUM(ps.ps_supplycost * ps.ps_availqty) DESC) AS rank
    FROM 
        supplier s
    JOIN 
        nation n ON s.s_nationkey = n.n_nationkey
    JOIN 
        partsupp ps ON s.s_suppkey = ps.ps_suppkey
    GROUP BY 
        s.s_name, n.n_name
),
TopSuppliers AS (
    SELECT 
        nation,
        s_name,
        total_cost
    FROM 
        RankedSuppliers
    WHERE 
        rank <= 5
)
SELECT 
    t.nation,
    LISTAGG(t.s_name, ', ') WITHIN GROUP (ORDER BY t.s_name) AS top_suppliers,
    LISTAGG(CAST(t.total_cost AS VARCHAR), ', ') WITHIN GROUP (ORDER BY t.total_cost) AS costs
FROM 
    TopSuppliers t
GROUP BY 
    t.nation
ORDER BY 
    t.nation;
