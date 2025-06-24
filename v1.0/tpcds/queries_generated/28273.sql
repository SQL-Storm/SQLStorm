
SELECT 
    ca_city,
    COUNT(DISTINCT c_customer_id) AS unique_customers,
    SUM(ws_net_paid) AS total_sales,
    AVG(LENGTH(c_first_name) + LENGTH(c_last_name)) AS avg_customer_name_length,
    STRING_AGG(DISTINCT ws_ship_mode_sk::TEXT, ', ') AS used_ship_modes,
    MAX(DATE_PART('year', d_date)) AS max_sales_year
FROM 
    customer_address ca
JOIN 
    customer c ON ca.ca_address_sk = c.c_current_addr_sk
JOIN 
    web_sales ws ON c.c_customer_sk = ws.ws_bill_customer_sk
JOIN 
    date_dim d ON ws.ws_sold_date_sk = d.d_date_sk
WHERE 
    ca_city IS NOT NULL
GROUP BY 
    ca_city
HAVING 
    COUNT(ws.ws_order_number) > 10
ORDER BY 
    unique_customers DESC, total_sales DESC
LIMIT 50;
