
WITH CustomerSales AS (
    SELECT c.c_customer_sk, c.c_first_name, c.c_last_name, SUM(ws.ws_ext_sales_price) AS total_sales
    FROM customer c
    JOIN web_sales ws ON c.c_customer_sk = ws.ws_ship_customer_sk
    WHERE ws.ws_sold_date_sk BETWEEN 2450000 AND 2451000
    GROUP BY c.c_customer_sk, c.c_first_name, c.c_last_name
),
TopCustomers AS (
    SELECT c.c_first_name, c.c_last_name, cs.total_sales, RANK() OVER (ORDER BY cs.total_sales DESC) as sales_rank
    FROM CustomerSales cs
    JOIN customer c ON cs.c_customer_sk = c.c_customer_sk
)
SELECT tc.c_first_name, tc.c_last_name, tc.total_sales
FROM TopCustomers tc
WHERE tc.sales_rank <= 10
ORDER BY tc.total_sales DESC;

-- Measure query performance with EXPLAIN ANALYZE or appropriate benchmarking tool.
