
WITH CustomerSales AS (
    SELECT 
        c.c_customer_id,
        SUM(ws.ws_ext_sales_price) AS total_web_sales,
        COUNT(DISTINCT ws.ws_order_number) AS order_count,
        DENSE_RANK() OVER (PARTITION BY c.c_customer_id ORDER BY SUM(ws.ws_ext_sales_price) DESC) AS sales_rank
    FROM 
        customer c
    LEFT JOIN 
        web_sales ws ON c.c_customer_sk = ws.ws_bill_customer_sk
    GROUP BY 
        c.c_customer_id
),
TopCustomers AS (
    SELECT 
        c.c_customer_id,
        cs.total_web_sales,
        cs.order_count
    FROM 
        CustomerSales cs
    JOIN 
        customer c ON cs.c_customer_id = c.c_customer_id
    WHERE 
        cs.sales_rank <= 10
),
DateSales AS (
    SELECT 
        d.d_date,
        SUM(ws.ws_ext_sales_price) AS daily_sales
    FROM 
        date_dim d
    LEFT JOIN 
        web_sales ws ON d.d_date_sk = ws.ws_sold_date_sk
    GROUP BY 
        d.d_date
),
SalesTrend AS (
    SELECT 
        d.d_date,
        daily_sales,
        LAG(daily_sales) OVER (ORDER BY d.d_date) AS previous_sales,
        CASE 
            WHEN previous_sales IS NULL THEN NULL
            ELSE ((daily_sales - previous_sales) / NULLIF(previous_sales, 0)) * 100
        END AS growth_percentage
    FROM 
        DateSales d
)

SELECT 
    tc.c_customer_id,
    tc.total_web_sales,
    tc.order_count,
    dt.d_date,
    dt.daily_sales,
    dt.growth_percentage
FROM 
    TopCustomers tc
LEFT JOIN 
    SalesTrend dt ON dt.d_date >= '2023-01-01' AND dt.d_date <= '2023-12-31'
ORDER BY 
    tc.total_web_sales DESC, dt.d_date;
