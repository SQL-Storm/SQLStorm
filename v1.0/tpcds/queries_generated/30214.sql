
WITH RECURSIVE SalesCTE AS (
    SELECT ws_bill_customer_sk, SUM(ws_ext_sales_price) AS total_sales,
           ROW_NUMBER() OVER (PARTITION BY ws_bill_customer_sk ORDER BY SUM(ws_ext_sales_price) DESC) AS rank
    FROM web_sales
    WHERE ws_sold_date_sk >= 2400 -- hypothetical date condition
    GROUP BY ws_bill_customer_sk
    HAVING SUM(ws_ext_sales_price) > 10000
), CustomerInfo AS (
    SELECT c.c_customer_sk, c.c_first_name, c.c_last_name,
           cd.cd_gender, cd.cd_marital_status, cd.cd_credit_rating,
           ROW_NUMBER() OVER (PARTITION BY c.c_customer_sk ORDER BY c.c_birth_year ASC) AS row_num
    FROM customer c
    JOIN customer_demographics cd ON c.c_current_cdemo_sk = cd.cd_demo_sk
    WHERE cd.cd_purchase_estimate > 5000
), AddressInfo AS (
    SELECT ca.ca_address_sk, ca.ca_city, ca.ca_state,
           COUNT(DISTINCT sa.ws_order_number) AS total_orders
    FROM customer_address ca
    LEFT JOIN web_sales sa ON ca.ca_address_sk = sa.ws_ship_addr_sk
    GROUP BY ca.ca_address_sk, ca.ca_city, ca.ca_state
), TopCustomers AS (
    SELECT b.ws_bill_customer_sk, b.total_sales,
           COALESCE(a.total_orders, 0) AS total_orders,
           CASE
               WHEN b.total_sales > 50000 THEN 'High'
               WHEN b.total_sales BETWEEN 20000 AND 50000 THEN 'Medium'
               ELSE 'Low'
           END AS customer_category
    FROM SalesCTE b
    LEFT JOIN AddressInfo a ON b.ws_bill_customer_sk = a.ca_address_sk
)
SELECT ci.c_first_name, ci.c_last_name, ci.cd_gender, ci.cd_marital_status,
       tc.total_sales, tc.total_orders, tc.customer_category
FROM TopCustomers tc
JOIN CustomerInfo ci ON tc.ws_bill_customer_sk = ci.c_customer_sk
WHERE tc.customer_category = 'High'
ORDER BY tc.total_sales DESC
LIMIT 10;

-- Including contribution by items sold
SELECT i.i_item_id, i.i_item_desc, SUM(ws.ws_quantity) AS total_quantity_sold
FROM web_sales ws
JOIN item i ON ws.ws_item_sk = i.i_item_sk
WHERE ws.ws_sold_date_sk BETWEEN 2400 AND 2405
GROUP BY i.i_item_id, i.i_item_desc
HAVING SUM(ws.ws_quantity) > 100
ORDER BY total_quantity_sold DESC
LIMIT 5;

-- Check for NULL values in demographic data
SELECT c.c_customer_sk, 
       COALESCE(cd.cd_gender, 'Not Specified') AS gender,
       COALESCE(cd.cd_marital_status, 'Not Specified') AS marital_status
FROM customer c
LEFT JOIN customer_demographics cd ON c.c_current_cdemo_sk = cd.cd_demo_sk
WHERE cd.cd_gender IS NULL OR cd.cd_marital_status IS NULL;
