
WITH CustomerStats AS (
    SELECT 
        c.c_customer_sk,
        c.c_first_name,
        c.c_last_name,
        cd.cd_gender,
        COUNT(DISTINCT ws.ws_order_number) AS total_orders,
        SUM(ws.ws_net_paid_inc_tax) AS total_spent,
        DENSE_RANK() OVER (PARTITION BY cd.cd_gender ORDER BY SUM(ws.ws_net_paid_inc_tax) DESC) AS spent_rank
    FROM customer c
    JOIN customer_demographics cd ON c.c_current_cdemo_sk = cd.cd_demo_sk
    LEFT JOIN web_sales ws ON c.c_customer_sk = ws.ws_bill_customer_sk
    GROUP BY c.c_customer_sk, c.c_first_name, c.c_last_name, cd.cd_gender
),
HighSpenders AS (
    SELECT 
        cs.*,
        CASE 
            WHEN cs.spent_rank <= 5 THEN 'Top 5'
            ELSE 'Not Top 5'
        END AS spender_category
    FROM CustomerStats cs
)
SELECT 
    h.c_first_name,
    h.c_last_name,
    h.total_orders,
    h.total_spent,
    COALESCE(h.spender_category, 'Unknown') AS spender_category,
    REPLACE(h.c_first_name || ' ' || h.c_last_name, ' ', '_') AS formatted_name
FROM HighSpenders h
WHERE h.spent_rank <= 10
ORDER BY h.total_spent DESC;

SELECT 
    'Store Sales' AS data_source, 
    ss.ss_sales_price,
    ss.ss_net_profit
FROM store_sales ss
WHERE ss.ss_sold_date_sk IN (
    SELECT d.d_date_sk 
    FROM date_dim d 
    WHERE d.d_year = 2023
) 
UNION ALL 
SELECT 
    'Catalog Sales' AS data_source, 
    cs.cs_sales_price,
    cs.cs_net_profit
FROM catalog_sales cs
WHERE cs.cs_sold_date_sk IN (
    SELECT d.d_date_sk 
    FROM date_dim d 
    WHERE d.d_year = 2023
)
ORDER BY data_source, ss_sales_price DESC NULLS LAST;
