
WITH AddressData AS (
    SELECT 
        ca_address_sk,
        TRIM(CONCAT(ca_street_number, ' ', ca_street_name, ' ', ca_street_type)) AS full_address,
        LOWER(ca_city) AS normalized_city,
        UPPER(ca_state) AS normalized_state
    FROM 
        customer_address
),
DemographicData AS (
    SELECT 
        cd_demo_sk,
        cd_gender,
        cd_marital_status,
        cd_education_status,
        CASE 
            WHEN cd_purchase_estimate >= 1000 THEN 'High'
            WHEN cd_purchase_estimate BETWEEN 500 AND 999 THEN 'Medium'
            ELSE 'Low'
        END AS purchase_band
    FROM 
        customer_demographics
),
CustomerData AS (
    SELECT 
        c_customer_sk,
        c_first_name,
        c_last_name,
        cd.gender AS gender,
        cd.marital_status AS marital_status,
        cd.purchase_band
    FROM 
        customer c
    JOIN 
        DemographicData cd ON c.c_current_cdemo_sk = cd.cd_demo_sk
),
SalesData AS (
    SELECT 
        ws_bill_customer_sk,
        SUM(ws_net_paid) AS total_sales,
        COUNT(ws_order_number) AS order_count
    FROM 
        web_sales
    GROUP BY 
        ws_bill_customer_sk
)
SELECT 
    c.customer_id,
    CONCAT(c.first_name, ' ', c.last_name) AS full_name,
    address.full_address,
    address.normalized_city,
    address.normalized_state,
    sales.total_sales,
    sales.order_count,
    CASE 
        WHEN sales.total_sales > 5000 THEN 'VIP'
        WHEN sales.total_sales BETWEEN 1000 AND 5000 THEN 'Regular'
        ELSE 'New'
    END AS customer_status
FROM 
    CustomerData c
JOIN 
    AddressData address ON c.current_addr_sk = address.ca_address_sk
LEFT JOIN 
    SalesData sales ON c.customer_sk = sales.ws_bill_customer_sk
WHERE 
    address.normalized_city LIKE 'new%' 
ORDER BY 
    sales.total_sales DESC
LIMIT 50;
