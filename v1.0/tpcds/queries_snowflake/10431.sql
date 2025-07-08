
SELECT c.c_customer_id, 
       c.c_first_name, 
       c.c_last_name, 
       ca.ca_city, 
       ca.ca_state, 
       SUM(ws.ws_sales_price) AS total_sales
FROM customer c
JOIN customer_address ca ON c.c_current_addr_sk = ca.ca_address_sk
JOIN web_sales ws ON c.c_customer_sk = ws.ws_bill_customer_sk
GROUP BY c.c_customer_id, c.c_first_name, c.c_last_name, ca.ca_city, ca.ca_state
HAVING SUM(ws.ws_sales_price) > 1000
ORDER BY total_sales DESC
FETCH FIRST 100 ROWS ONLY;
