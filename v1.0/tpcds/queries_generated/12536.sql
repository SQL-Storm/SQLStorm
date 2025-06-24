
SELECT 
    c.c_customer_id,
    SUM(ss.ss_quantity) AS total_quantity,
    SUM(ss.ss_sales_price) AS total_sales,
    AVG(ss.ss_net_profit) AS avg_profit
FROM 
    customer AS c
JOIN 
    store_sales AS ss ON c.c_customer_sk = ss.ss_customer_sk
JOIN 
    date_dim AS d ON ss.ss_sold_date_sk = d.d_date_sk
WHERE 
    d.d_year = 2023
GROUP BY 
    c.c_customer_id
HAVING 
    total_sales > 1000
ORDER BY 
    total_sales DESC
LIMIT 100;
