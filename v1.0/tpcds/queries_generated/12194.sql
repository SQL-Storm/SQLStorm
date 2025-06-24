
SELECT 
    c.c_customer_id,
    ca.ca_city,
    SUM(cs.cs_sales_price) AS total_sales,
    COUNT(DISTINCT cs.cs_order_number) AS total_orders
FROM 
    customer c
JOIN 
    customer_address ca ON c.c_current_addr_sk = ca.ca_address_sk
JOIN 
    store_sales cs ON c.c_customer_sk = cs.ss_customer_sk
JOIN 
    date_dim d ON cs.ss_sold_date_sk = d.d_date_sk
WHERE 
    d.d_year = 2023
GROUP BY 
    c.c_customer_id, ca.ca_city
ORDER BY 
    total_sales DESC
LIMIT 100;
