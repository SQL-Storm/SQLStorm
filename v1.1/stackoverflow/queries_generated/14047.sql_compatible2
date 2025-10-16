WITH cte AS (
  SELECT
    p.Id AS post_id,
    p.Title,
    p.Body,
    p.Tags,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.AnswerCount,
    CASE WHEN p.PostTypeId = 1 THEN 'Question' ELSE 'Answer' END AS post_type,
    CASE WHEN p.ClosedDate IS NULL THEN 'Open' ELSE 'Closed' END AS post_status,
    COALESCE(u.DisplayName, 'Deleted User') AS owner_display_name,
    u.Reputation,
    u.UpVotes,
    u.DownVotes,
    u.Views,
    CAST('2024-10-01 12:34:56' AS TIMESTAMP) - p.CreationDate AS interval_since_creation,
    EXTRACT(day FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - COALESCE(p.ClosedDate, p.CreationDate))) AS days_since_closed,
    EXTRACT(day FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - p.CreationDate)) AS days_since_creation,
    DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS user_post_rank,
    RANK() OVER (ORDER BY p.Score DESC) AS post_score_rank
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
),
tag_counts AS (
  SELECT
    tag,
    COUNT(*) AS tag_count
  FROM (
    SELECT
      UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><')) AS tag
    FROM cte p
  ) t
  GROUP BY tag
  ORDER BY tag_count DESC
  LIMIT 50
),
popular_tags AS (
  SELECT
    tag,
    tag_count,
    ROUND(CAST(tag_count AS DECIMAL) * 1.0 / (SELECT SUM(tag_count) FROM tag_counts), 2) AS tag_percentage
  FROM tag_counts
),
user_reputation_stats AS (
  SELECT
    OwnerUserId,
    AVG(Reputation) AS avg_reputation,
    SUM(UpVotes) AS total_upvotes,
    SUM(DownVotes) AS total_downvotes,
    SUM(Views) AS total_views
  FROM cte
  GROUP BY OwnerUserId
),
active_users AS (
  SELECT
    u.Id AS user_id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    EXTRACT(day FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - u.LastAccessDate)) AS days_since_last_access,
    u.UpVotes,
    u.DownVotes,
    u.Views,
    (SELECT avg_reputation FROM user_reputation_stats WHERE OwnerUserId = u.Id) AS avg_reputation,
    (SELECT total_upvotes FROM user_reputation_stats WHERE OwnerUserId = u.Id) AS total_upvotes,
    (SELECT total_downvotes FROM user_reputation_stats WHERE OwnerUserId = u.Id) AS total_downvotes,
    (SELECT total_views FROM user_reputation_stats WHERE OwnerUserId = u.Id) AS total_views
  FROM Users u
  WHERE u.Id IN (
    SELECT DISTINCT OwnerUserId
    FROM cte
  )
  AND EXTRACT(day FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - u.LastAccessDate)) < 365
)
SELECT
  cte.post_id,
  cte.Title,
  cte.Body,
  cte.Tags,
  cte.owner_display_name,
  cte.post_type,
  cte.post_status,
  cte.Reputation,
  cte.UpVotes,
  cte.DownVotes,
  cte.Views,
  cte.days_since_creation,
  cte.days_since_closed,
  cte.user_post_rank,
  cte.post_score_rank,
  pt.tag,
  pt.tag_count,
  pt.tag_percentage,
  au.DisplayName AS active_user_name,
  au.Reputation AS active_user_reputation,
  au.days_since_last_access,
  au.total_upvotes AS active_user_total_upvotes,
  au.total_downvotes AS active_user_total_downvotes,
  au.total_views AS active_user_total_views,
  au.avg_reputation AS active_user_avg_reputation
FROM cte
LEFT JOIN popular_tags pt ON POSITION(pt.tag IN SUBSTRING(cte.Tags FROM 2 FOR LENGTH(cte.Tags) - 2)) > 0
LEFT JOIN active_users au ON cte.OwnerUserId = au.user_id
ORDER BY cte.post_id;