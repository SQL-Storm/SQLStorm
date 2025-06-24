SELECT SUM(l_extendedprice) * (1 - l_discount) AS revenue
FROM lineitem
WHERE l_shipdate BETWEEN DATE '1994-01-01' AND DATE '1994-12-31'
  AND l_discount BETWEEN 0.05 AND 0.07
  AND l_quantity < 24;
