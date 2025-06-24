
SELECT 
    c.c_customer_id, 
    c.c_first_name, 
    c.c_last_name, 
    a.ca_city, 
    a.ca_state, 
    SUM(ws.net_paid) AS total_spent
FROM 
    customer c
JOIN 
    customer_address a ON c.c_current_addr_sk = a.ca_address_sk
JOIN 
    web_sales ws ON c.c_customer_sk = ws.ws_bill_customer_sk
WHERE 
    a.ca_state IN ('NY', 'CA')
GROUP BY 
    c.c_customer_id, c.c_first_name, c.c_last_name, a.ca_city, a.ca_state
ORDER BY 
    total_spent DESC
LIMIT 100;
