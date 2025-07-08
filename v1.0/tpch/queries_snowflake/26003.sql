
WITH PartDetails AS (
    SELECT 
        p.p_partkey,
        p.p_name,
        p.p_brand,
        p.p_type,
        p.p_size,
        p.p_retailprice,
        p.p_comment,
        ps.ps_availqty,
        ps.ps_supplycost,
        s.s_name AS supplier_name,
        s.s_nationkey,
        n.n_name AS nation_name
    FROM 
        part p
    JOIN 
        partsupp ps ON p.p_partkey = ps.ps_partkey
    JOIN 
        supplier s ON ps.ps_suppkey = s.s_suppkey
    JOIN 
        nation n ON s.s_nationkey = n.n_nationkey
),
CustomerOrders AS (
    SELECT 
        c.c_custkey,
        c.c_name,
        o.o_orderkey,
        o.o_orderdate,
        o.o_totalprice,
        o.o_comment
    FROM 
        customer c
    JOIN 
        orders o ON c.c_custkey = o.o_custkey
    WHERE 
        o.o_orderstatus = 'O'
),
OrdersWithLineItems AS (
    SELECT 
        co.o_orderkey,
        pd.p_partkey,
        pd.p_name,
        pd.p_brand,
        pd.p_type,
        pd.p_size,
        pd.p_retailprice,
        pd.p_comment,
        pd.ps_availqty,
        pd.ps_supplycost,
        pd.supplier_name,
        pd.nation_name,
        co.o_totalprice
    FROM 
        CustomerOrders co
    JOIN 
        lineitem l ON l.l_orderkey = co.o_orderkey
    JOIN 
        PartDetails pd ON pd.p_partkey = l.l_partkey
)
SELECT 
    p.p_partkey,
    p.p_name,
    p.p_brand,
    p.p_type,
    p.p_size,
    p.p_retailprice,
    p.p_comment,
    p.ps_availqty,
    p.ps_supplycost,
    p.supplier_name,
    p.nation_name,
    COUNT(co.o_orderkey) AS total_orders,
    AVG(co.o_totalprice) AS avg_order_value
FROM 
    OrdersWithLineItems co
GROUP BY 
    p.p_partkey, p.p_name, p.p_brand, p.p_type, p.p_size, 
    p.p_retailprice, p.p_comment, p.ps_availqty, 
    p.ps_supplycost, p.supplier_name, p.nation_name
ORDER BY 
    avg_order_value DESC 
LIMIT 10;
