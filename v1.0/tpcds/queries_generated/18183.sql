
SELECT ca.city, COUNT(*) as customer_count 
FROM customer c 
JOIN customer_address ca ON c.c_current_addr_sk = ca.ca_address_sk 
GROUP BY ca.city 
ORDER BY customer_count DESC 
LIMIT 10;
