
SELECT
    ca.city AS customer_city,
    COUNT(DISTINCT c.c_customer_sk) AS customer_count,
    SUM(ws.ws_sales_price) AS total_sales,
    AVG(ws.ws_sales_price) AS average_sales_price
FROM
    customer c
JOIN
    customer_address ca ON c.c_current_addr_sk = ca.ca_address_sk
JOIN
    web_sales ws ON c.c_customer_sk = ws.ws_bill_customer_sk
JOIN
    date_dim d ON ws.ws_sold_date_sk = d.d_date_sk
WHERE
    d.d_year = 2023
GROUP BY
    ca.city
ORDER BY
    total_sales DESC
LIMIT 10;
