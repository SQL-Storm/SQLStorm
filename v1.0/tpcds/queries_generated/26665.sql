
SELECT 
    ca_state, 
    ca_city, 
    COUNT(CASE WHEN cd_gender = 'F' THEN 1 END) AS female_count, 
    COUNT(CASE WHEN cd_gender = 'M' THEN 1 END) AS male_count, 
    SUM(CASE WHEN cd_marital_status = 'M' THEN 1 ELSE 0 END) AS married_count, 
    SUM(CASE WHEN cd_marital_status = 'S' THEN 1 ELSE 0 END) AS single_count, 
    AVG(cd_dep_count) AS avg_dependents, 
    AVG(cd_purchase_estimate) AS avg_purchase_estimate
FROM 
    customer_address ca 
JOIN 
    customer c ON ca.ca_address_sk = c.c_current_addr_sk 
JOIN 
    customer_demographics cd ON c.c_current_cdemo_sk = cd.cd_demo_sk 
WHERE 
    ca.city IS NOT NULL 
GROUP BY 
    ca_state, ca_city 
ORDER BY 
    ca_state, ca_city;
