SELECT 
  CONCAT(
    LOWER(u.DisplayName),
    '_',
    CAST(FLOOR(RANDOM() * 1000000) AS VARCHAR(10))
  ) AS user_name,
  CASE
    WHEN RANDOM() < 0.7 THEN 'active'
    ELSE 'inactive'
  END AS user_status,
  CASE
    WHEN RANDOM() < 0.5 THEN 'gold'
    WHEN RANDOM() < 0.8 THEN 'silver'
    ELSE 'bronze'
  END AS badge_class,
  CAST(FLOOR(RANDOM() * 10000) AS INTEGER) AS reputation,
  CAST(FLOOR(RANDOM() * 3650) AS INTEGER) AS days_since_creation,
  CAST(FLOOR(RANDOM() * 365) AS INTEGER) AS days_since_last_access,
  CAST(FLOOR(RANDOM() * 10000) AS INTEGER) AS views,
  CAST(FLOOR(RANDOM() * 5000) AS INTEGER) AS upvotes,
  CAST(FLOOR(RANDOM() * 2000) AS INTEGER) AS downvotes,
  CASE
    WHEN RANDOM() < 0.2 THEN 'https://example.com/profile.jpg'
    ELSE NULL
  END AS profile_image_url,
  CASE
    WHEN RANDOM() < 0.1 THEN 'johndoe@example.com'
    ELSE NULL
  END AS email_hash,
  CAST(FLOOR(RANDOM() * 100000) + 1 AS INTEGER) AS account_id
FROM
  (
    SELECT 1 AS n
    UNION ALL
    SELECT 2
    UNION ALL
    SELECT 3
    UNION ALL
    SELECT 4
    UNION ALL
    SELECT 5
  ) AS generate_users
CROSS JOIN
  (
    SELECT 1 AS m
    UNION ALL
    SELECT 2
    UNION ALL
    SELECT 3
  ) AS generate_badges
CROSS JOIN
  (SELECT 'user' AS DisplayName) AS u
GROUP BY
  u.DisplayName,
  generate_users.n,
  generate_badges.m
ORDER BY
  user_name;