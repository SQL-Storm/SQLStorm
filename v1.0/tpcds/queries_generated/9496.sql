
SELECT 
    ca_state, 
    COUNT(DISTINCT c_customer_sk) AS unique_customers,
    SUM(ws_quantity) AS total_quantity_sold,
    SUM(ws_net_profit) AS total_net_profit
FROM 
    customer_address AS ca
JOIN 
    customer AS c ON ca.ca_address_sk = c.c_current_addr_sk
JOIN 
    web_sales AS ws ON c.c_customer_sk = ws.ws_ship_customer_sk
JOIN 
    date_dim AS d ON ws.ws_sold_date_sk = d.d_date_sk
WHERE 
    d.d_year = 2023 AND 
    d.d_moy IN (11, 12) -- November and December
GROUP BY 
    ca_state
ORDER BY 
    total_net_profit DESC
LIMIT 10;
