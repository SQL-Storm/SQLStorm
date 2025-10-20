WITH popular_tags AS (
  SELECT t.TagName, COUNT(*) AS question_count
  FROM Tags t
  JOIN Posts p ON POSITION(t.TagName IN p.Tags) > 0
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '365' DAY
  GROUP BY t.TagName
  HAVING COUNT(*) >= 50
),
active_users AS (
  SELECT u.Id, u.Reputation, u.UpVotes
  FROM Users u
  WHERE u.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '730' DAY
    AND u.LastAccessDate >= CAST('2024-10-01' AS DATE) - INTERVAL '30' DAY
),
monthly_stats AS (
  SELECT
    DATE_TRUNC('month', p.CreationDate) AS month,
    COUNT(DISTINCT p.Id) AS questions_asked,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS answers_given,
    AVG(p.Score) AS avg_score,
    SUM(p.ViewCount) AS total_views
  FROM Posts p
  WHERE p.PostTypeId IN (1, 2)
    AND p.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '24' MONTH
  GROUP BY DATE_TRUNC('month', p.CreationDate)
),
user_engagement AS (
  SELECT
    u.Id AS user_id,
    u.DisplayName,
    COUNT(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN 1 END) AS edits_made,
    COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS upvotes_cast,
    COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS downvotes_cast,
    AVG(EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate)) / 86400.0) AS avg_post_age_days,
    COUNT(p.Id) AS cnt_posts
  FROM Users u
  JOIN Posts p ON u.Id = p.OwnerUserId OR u.Id = p.LastEditorUserId
  LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.UserId = u.Id
  LEFT JOIN Votes v ON p.Id = v.PostId AND v.UserId = u.Id
  WHERE u.Reputation > 100
    AND p.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '365' DAY
  GROUP BY u.Id, u.DisplayName
  HAVING COUNT(p.Id) >= 5
),
posts_tags_by_month AS (
  SELECT
    DATE_TRUNC('month', p.CreationDate) AS month,
    TRIM(tag) AS tag
  FROM Posts p
  CROSS JOIN LATERAL (
    SELECT regexp_split_to_table(
      CASE
        WHEN LEFT(p.Tags,1) = '<' AND RIGHT(p.Tags,1) = '>' THEN SUBSTRING(p.Tags FROM 2 FOR (LENGTH(p.Tags) - 2))
        ELSE p.Tags
      END,
      '><'
    ) AS tag
  ) s
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '24' MONTH
),
tag_presence_in_month AS (
  SELECT month, tag, COUNT(*) AS cnt
  FROM posts_tags_by_month
  GROUP BY month, tag
)
SELECT
  pt.TagName,
  ms.month,
  COALESCE(ue.user_id, 0) AS active_user_id,
  COALESCE(ue.DisplayName, 'Community') AS user_name,
  COALESCE(ue.edits_made, 0) AS edits,
  COALESCE(ue.upvotes_cast, 0) AS upvotes,
  ms.questions_asked,
  ms.answers_given,
  ms.avg_score,
  ms.total_views,
  ROW_NUMBER() OVER (PARTITION BY pt.TagName ORDER BY ms.total_views DESC) AS popularity_rank,
  LAG(ms.total_views) OVER (PARTITION BY pt.TagName ORDER BY ms.month) AS prev_month_views
FROM popular_tags pt
CROSS JOIN monthly_stats ms
LEFT JOIN (
  SELECT
    au.Id AS user_id,
    au.Reputation,
    ue.DisplayName,
    ue.edits_made,
    ue.upvotes_cast,
    ue.downvotes_cast
  FROM active_users au
  JOIN user_engagement ue ON au.Id = ue.user_id
  WHERE ue.upvotes_cast > ue.downvotes_cast * 2
    AND au.Reputation >= 500
) ue ON EXTRACT(MONTH FROM ms.month) = EXTRACT(MONTH FROM (CAST('2024-10-01' AS DATE) - INTERVAL '1' MONTH))
WHERE ms.month >= CAST('2024-10-01' AS DATE) - INTERVAL '12' MONTH
  AND EXISTS (
    SELECT 1
    FROM tag_presence_in_month tpm
    WHERE tpm.month = ms.month
      AND tpm.tag = pt.TagName
  )
GROUP BY
  pt.TagName,
  ms.month,
  ue.user_id,
  ue.DisplayName,
  ue.edits_made,
  ue.upvotes_cast,
  ms.questions_asked,
  ms.answers_given,
  ms.avg_score,
  ms.total_views
ORDER BY pt.TagName, ms.month DESC, ms.total_views DESC
LIMIT 1000;