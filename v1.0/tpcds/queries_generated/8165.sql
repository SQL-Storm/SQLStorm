
WITH CustomerSales AS (
    SELECT 
        c.c_customer_sk,
        c.c_first_name,
        c.c_last_name,
        SUM(ws.ws_ext_sales_price) AS total_sales,
        COUNT(ws.ws_order_number) AS order_count
    FROM customer c
    JOIN web_sales ws ON c.c_customer_sk = ws.ws_bill_customer_sk
    JOIN date_dim d ON ws.ws_sold_date_sk = d.d_date_sk
    WHERE d.d_year = 2023
    GROUP BY c.c_customer_sk, c.c_first_name, c.c_last_name
),
TopCustomers AS (
    SELECT 
        c.*,
        ROW_NUMBER() OVER (ORDER BY cs.total_sales DESC) AS rank
    FROM CustomerSales cs
    JOIN customer c ON cs.c_customer_sk = c.c_customer_sk
)
SELECT 
    tc.c_first_name,
    tc.c_last_name,
    tc.total_sales,
    tc.order_count,
    d.d_month as sales_month
FROM TopCustomers tc
JOIN date_dim d ON d.d_year = 2023 AND d.d_month_seq = (SELECT MONTH(DATE_SUB(CURDATE(), INTERVAL 1 MONTH))) 
WHERE tc.rank <= 10
ORDER BY tc.total_sales DESC;
