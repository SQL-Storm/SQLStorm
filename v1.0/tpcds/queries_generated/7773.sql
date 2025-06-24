
WITH CustomerPurchases AS (
    SELECT 
        c.c_customer_sk,
        c.c_first_name,
        c.c_last_name,
        SUM(ws.ws_quantity) AS total_quantity,
        SUM(ws.ws_net_paid) AS total_spent,
        COUNT(ws.ws_order_number) AS order_count
    FROM 
        customer c
    JOIN 
        web_sales ws ON c.c_customer_sk = ws.ws_bill_customer_sk
    WHERE 
        ws.ws_sold_date_sk BETWEEN 2458488 AND 2458534  -- Filter by a specified date range
    GROUP BY 
        c.c_customer_sk, c.c_first_name, c.c_last_name
),
TopCustomers AS (
    SELECT 
        *,
        RANK() OVER (ORDER BY total_spent DESC) AS spending_rank
    FROM 
        CustomerPurchases
)
SELECT 
    tc.c_customer_sk,
    tc.c_first_name,
    tc.c_last_name,
    tc.total_quantity,
    tc.total_spent
FROM 
    TopCustomers tc
WHERE 
    tc.spending_rank <= 10  -- Top 10 customers by total spent
ORDER BY 
    tc.total_spent DESC;
