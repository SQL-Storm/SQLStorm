
WITH RankedSales AS (
    SELECT 
        ws_item_sk,
        ws_sales_price,
        ws_quantity,
        ws_ext_sales_price,
        ROW_NUMBER() OVER (PARTITION BY ws_item_sk ORDER BY ws_sales_price DESC) AS rank_price,
        ROW_NUMBER() OVER (PARTITION BY ws_item_sk ORDER BY ws_quantity DESC) AS rank_quantity
    FROM 
        web_sales
    WHERE 
        ws_sales_price IS NOT NULL
),
SalesSummary AS (
    SELECT 
        rs.ws_item_sk,
        SUM(rs.ws_ext_sales_price) AS total_sales_price,
        AVG(rs.ws_sales_price) AS avg_price,
        MAX(rs.ws_quantity) AS max_quantity,
        MIN(rs.ws_quantity) AS min_quantity
    FROM 
        RankedSales rs
    WHERE 
        rs.rank_price <= 3 OR rs.rank_quantity <= 3
    GROUP BY 
        rs.ws_item_sk
)
SELECT 
    sa.ws_item_sk,
    sa.total_sales_price,
    sa.avg_price,
    sa.max_quantity,
    sa.min_quantity,
    CASE 
        WHEN sa.total_sales_price IS NULL THEN 'No Sales'
        ELSE CASE 
             WHEN sa.avg_price = 0 THEN 'Zero Average Price'
             ELSE 'Sales Data Available'
             END
    END AS sales_flag,
    COALESCE(
        (SELECT SUM(cr_return_quantity) 
         FROM catalog_returns cr 
         WHERE cr.cr_item_sk = sa.ws_item_sk), 0) AS total_returns,
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM store s 
            INNER JOIN inventory i ON s.s_store_sk = i.inv_warehouse_sk 
            WHERE i.inv_item_sk = sa.ws_item_sk AND i.inv_quantity_on_hand < 10
        ) THEN 'Low Inventory'
        ELSE 'Sufficient Inventory'
    END AS inventory_status
FROM 
    SalesSummary sa
LEFT JOIN 
    customer_demographics cd ON cd.cd_demo_sk = (
        SELECT MIN(c.c_current_cdemo_sk) 
        FROM customer c 
        WHERE c.c_customer_sk = (SELECT MIN(ws_bill_customer_sk) 
                                  FROM web_sales ws 
                                  WHERE ws.ws_item_sk = sa.ws_item_sk)
    )
WHERE 
    sa.avg_price IS NOT NULL AND sa.total_sales_price > 1000
ORDER BY 
    sa.avg_price DESC, sales_flag;
