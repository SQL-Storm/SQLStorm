-- {"query": "44063.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 465}
Here is an elaborate SQL query for performance benchmarking using the StackOverflow database schema:

WITH posts_by_month AS (
  SELECT 
    DATE_TRUNC('month', CreationDate) AS month_date,
    COUNT(*) AS post_count
  FROM Posts
  WHERE CreationDate >= '2020-01-01'
  GROUP BY 1
  ORDER BY 1
),
user_rep_changes AS (
  SELECT
    UserId,
    MAX(Reputation) AS max_reputation,
    MIN(Reputation) AS min_reputation,
    MAX(Reputation) - MIN(Reputation) AS reputation_change
  FROM Users
  GROUP BY UserId
),
popular_tags AS (
  SELECT
    TagName,
    COUNT(*) AS post_count
  FROM Posts
  CROSS JOIN UNNEST(STRING_TO_ARRAY(SUBSTRING(Tags, 2, LENGTH(Tags) - 2), '><')) AS tag
  WHERE CreationDate >= '2020-01-01'
  GROUP BY 1
  ORDER BY 2 DESC
  LIMIT 10
),
active_users AS (
  SELECT
    OwnerUserId,
    COUNT(*) AS post_count
  FROM Posts
  WHERE CreationDate >= '2020-01-01'
  GROUP BY 1
  ORDER BY 2 DESC
  LIMIT 10
)
SELECT
  p.month_date,
  p.post_count AS new_posts_per_month,
  r.max_reputation,
  r.min_reputation,
  r.reputation_change,
  t.TagName,
  t.post_count AS posts_with_popular_tag,
  u.post_count AS posts_by_active_users
FROM posts_by_month p
CROSS JOIN user_rep_changes r
CROSS JOIN popular_tags t
CROSS JOIN active_users u
ORDER BY p.month_date;
