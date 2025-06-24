
SELECT 
    c.c_customer_id,
    c.c_first_name,
    c.c_last_name,
    SUM(ss.ss_sales_price) AS total_sales,
    COUNT(ss.ss_ticket_number) AS total_transactions
FROM 
    customer c
JOIN 
    store_sales ss ON c.c_customer_sk = ss.ss_customer_sk
WHERE 
    ss.ss_sold_date_sk BETWEEN 20220101 AND 20221231
GROUP BY 
    c.c_customer_id, c.c_first_name, c.c_last_name
ORDER BY 
    total_sales DESC
LIMIT 100;
