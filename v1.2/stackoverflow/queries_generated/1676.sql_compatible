WITH ReputationalRiser AS (
  SELECT
    u.id,
    u.DisplayName,
    u.Reputation,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS rn
  FROM users u
)
SELECT
  r.id,
  r.DisplayName,
  r.Reputation,
  r.rn
FROM ReputationalRiser r
ORDER BY r.Reputation DESC;