WITH RevenueByNation AS (
    SELECT
        n.n_name AS Nation,
        SUM(l.l_extendedprice * (1 - l.l_discount)) AS TotalRevenue
    FROM
        lineitem l
    JOIN
        orders o ON l.l_orderkey = o.o_orderkey
    JOIN
        customer c ON o.o_custkey = c.c_custkey
    JOIN
        nation n ON c.c_nationkey = n.n_nationkey
    WHERE
        o.o_orderdate >= DATE '2023-01-01'
        AND o.o_orderdate < DATE '2023-12-31'
    GROUP BY
        n.n_name
),
TopNations AS (
    SELECT
        Nation,
        TotalRevenue,
        RANK() OVER (ORDER BY TotalRevenue DESC) AS RevenueRank
    FROM
        RevenueByNation
)
SELECT
    Nation,
    TotalRevenue
FROM
    TopNations
WHERE
    RevenueRank <= 5
ORDER BY
    TotalRevenue DESC;
