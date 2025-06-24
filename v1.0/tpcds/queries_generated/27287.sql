
WITH CustomerInfo AS (
    SELECT 
        c.c_customer_sk,
        CONCAT(c.c_first_name, ' ', c.c_last_name) AS full_name,
        cd.cd_gender,
        cd.cd_marital_status,
        cd.cd_education_status,
        ca.ca_city,
        ca.ca_state,
        ca.ca_country,
        ca.ca_zip,
        COUNT(sr.returned_date_sk) AS total_returns
    FROM customer c
    JOIN customer_demographics cd ON c.c_current_cdemo_sk = cd.cd_demo_sk
    JOIN customer_address ca ON c.c_current_addr_sk = ca.ca_address_sk
    LEFT JOIN store_returns sr ON c.c_customer_sk = sr.sr_customer_sk
    GROUP BY 
        c.c_customer_sk,
        c.c_first_name,
        c.c_last_name,
        cd.cd_gender,
        cd.cd_marital_status,
        cd.cd_education_status,
        ca.ca_city,
        ca.ca_state,
        ca.ca_country,
        ca.ca_zip
),
FilteredInfo AS (
    SELECT 
        *,
        CASE 
            WHEN cd_marital_status = 'S' THEN 'Single'
            WHEN cd_marital_status = 'M' THEN 'Married'
            ELSE 'Other'
        END AS marital_status_description
    FROM CustomerInfo
    WHERE total_returns > 0
)
SELECT 
    full_name,
    cd_gender,
    marital_status_description,
    ca_city,
    ca_state,
    ca_country,
    ca_zip,
    total_returns
FROM FilteredInfo
ORDER BY total_returns DESC
LIMIT 100;
