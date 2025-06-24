
SELECT 
    d.d_year, 
    c.c_gender, 
    SUM(ws.ws_sales_price) AS total_sales 
FROM 
    web_sales ws 
JOIN 
    customer c ON ws.ws_bill_customer_sk = c.c_customer_sk 
JOIN 
    date_dim d ON ws.ws_sold_date_sk = d.d_date_sk 
WHERE 
    d.d_year = 2023 
GROUP BY 
    d.d_year, c.c_gender 
ORDER BY 
    d.d_year, c.c_gender;
