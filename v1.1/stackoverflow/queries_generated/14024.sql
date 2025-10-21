-- {"query": "14024.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 488}
SELECT 
  CONCAT(
    LOWER(u.DisplayName), 
    '_', 
    CAST(FLOOR(RAND() * 1000000) AS VARCHAR(10))
  ) AS user_name,
  CASE
    WHEN RAND() < 0.7 THEN 'active'
    ELSE 'inactive'
  END AS user_status,
  CASE
    WHEN RAND() < 0.5 THEN 'gold'
    WHEN RAND() < 0.8 THEN 'silver'
    ELSE 'bronze'
  END AS badge_class,
  ROUND(RAND() * 10000, 0) AS reputation,
  FLOOR(RAND() * 3650) AS days_since_creation,
  FLOOR(RAND() * 365) AS days_since_last_access,
  ROUND(RAND() * 10000, 0) AS views,
  ROUND(RAND() * 5000, 0) AS upvotes,
  ROUND(RAND() * 2000, 0) AS downvotes,
  CASE
    WHEN RAND() < 0.2 THEN 'https://example.com/profile.jpg'
    ELSE NULL
  END AS profile_image_url,
  CASE
    WHEN RAND() < 0.1 THEN 'johndoe@example.com'
    ELSE NULL
  END AS email_hash,
  FLOOR(RAND() * 100000) + 1 AS account_id
FROM
  (
    SELECT 1
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
    SELECT 1
    UNION ALL
    SELECT 2
    UNION ALL
    SELECT 3
  ) AS generate_badges
ORDER BY
  user_name;
