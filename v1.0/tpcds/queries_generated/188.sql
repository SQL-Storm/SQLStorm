
WITH CustomerSales AS (
    SELECT 
        c.c_customer_sk,
        c.c_first_name,
        c.c_last_name,
        SUM(ws.ws_net_profit) AS total_net_profit,
        COUNT(ws.ws_order_number) AS total_orders
    FROM 
        customer c
    LEFT JOIN 
        web_sales ws ON c.c_customer_sk = ws.ws_bill_customer_sk
    GROUP BY 
        c.c_customer_sk, c.c_first_name, c.c_last_name
), 
TopCustomers AS (
    SELECT 
        *,
        RANK() OVER (ORDER BY total_net_profit DESC) AS profit_rank
    FROM 
        CustomerSales
    WHERE 
        total_orders > 5
), 
CustomerDemographics AS (
    SELECT 
        cd.cd_demo_sk,
        cd.cd_gender,
        cd.cd_marital_status,
        cd.cd_education_status
    FROM 
        customer_demographics cd
    JOIN 
        customer c ON c.c_current_cdemo_sk = cd.cd_demo_sk
)

SELECT 
    tc.c_first_name, 
    tc.c_last_name,
    tc.total_net_profit,
    cd.cd_gender,
    cd.cd_marital_status,
    cd.cd_education_status
FROM 
    TopCustomers tc
JOIN 
    CustomerDemographics cd ON tc.c_customer_sk = cd.cd_demo_sk
WHERE 
    tc.profit_rank <= 10
ORDER BY 
    tc.total_net_profit DESC;

-- Getting store details with profit summaries for popular store
SELECT 
    s.s_store_name, 
    COUNT(ss.ss_ticket_number) AS total_sales,
    SUM(ss.ss_net_profit) AS total_profit,
    AVG(ss.ss_sales_price) AS avg_sales_price
FROM 
    store s
JOIN 
    store_sales ss ON s.s_store_sk = ss.ss_store_sk
GROUP BY 
    s.s_store_name
HAVING 
    total_sales > 1000
ORDER BY 
    total_profit DESC
LIMIT 5;
