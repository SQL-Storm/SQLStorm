
WITH RECURSIVE sales_analysis AS (
    SELECT 
        c.c_customer_sk,
        c.c_first_name,
        c.c_last_name,
        SUM(ws.ws_net_profit) AS total_profit,
        COUNT(ws.ws_order_number) AS order_count,
        ROW_NUMBER() OVER (PARTITION BY c.c_customer_sk ORDER BY SUM(ws.ws_net_profit) DESC) AS rank
    FROM 
        customer c
    JOIN 
        web_sales ws ON c.c_customer_sk = ws.ws_bill_customer_sk
    WHERE 
        ws.ws_ship_date_sk >= (SELECT d.d_date_sk FROM date_dim d WHERE d.d_date = CURRENT_DATE - INTERVAL '1 year')
    GROUP BY 
        c.c_customer_sk, c.c_first_name, c.c_last_name
),
top_customers AS (
    SELECT 
        c.c_customer_sk,
        c.c_first_name,
        c.c_last_name,
        sa.total_profit,
        sa.order_count
    FROM 
        sales_analysis sa
    JOIN 
        customer c ON c.c_customer_sk = sa.c_customer_sk
    WHERE 
        sa.rank <= 10
),
customer_gender AS (
    SELECT 
        cd.cd_gender,
        SUM(total_profit) AS gender_profit
    FROM 
        top_customers tc
    JOIN 
        customer_demographics cd ON tc.c_customer_sk = cd.cd_demo_sk
    GROUP BY 
        cd.cd_gender
)
SELECT 
    COALESCE(g.cd_gender, 'Unknown') AS gender,
    g.gender_profit,
    tc.total_profit,
    (SELECT AVG(total_profit) FROM top_customers) AS avg_profit
FROM 
    customer_gender g
FULL OUTER JOIN 
    top_customers tc ON g.cd_gender = (SELECT cd.cd_gender FROM customer_demographics cd WHERE cd.cd_demo_sk = tc.c_customer_sk)
ORDER BY 
    gender_profit DESC;
