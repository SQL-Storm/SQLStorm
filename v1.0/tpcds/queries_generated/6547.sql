
SELECT 
    c.c_customer_id,
    ca.ca_city,
    cd.cd_gender,
    COUNT(DISTINCT ws.ws_order_number) AS total_orders,
    SUM(ws.ws_net_paid) AS total_revenue,
    AVG(ws.ws_net_profit) AS average_profit,
    MAX(ws.ws_sales_price) AS max_sales_price,
    MIN(ws.ws_sales_price) AS min_sales_price,
    DATE(d.d_date) AS transaction_date
FROM 
    customer c
JOIN 
    customer_address ca ON c.c_current_addr_sk = ca.ca_address_sk
JOIN 
    customer_demographics cd ON c.c_current_cdemo_sk = cd.cd_demo_sk
JOIN 
    web_sales ws ON c.c_customer_sk = ws.ws_bill_customer_sk
JOIN 
    date_dim d ON ws.ws_sold_date_sk = d.d_date_sk
WHERE 
    d.d_year = 2023
    AND ws.ws_net_paid > 0
GROUP BY 
    c.c_customer_id, ca.ca_city, cd.cd_gender, DATE(d.d_date)
HAVING 
    total_orders > 5
ORDER BY 
    total_revenue DESC;
