WITH popular_tags AS (
  SELECT t.TagName, COUNT(*) AS question_count
  FROM Tags t
  JOIN Posts p ON position(t.TagName in p.Tags) > 0
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= cast('2024-10-01' as date) - INTERVAL '365 days'
  GROUP BY t.TagName
  HAVING COUNT(*) >= 50
),
active_users AS (
  SELECT u.Id, u.Reputation, u.UpVotes
  FROM Users u
  WHERE u.CreationDate >= cast('2024-10-01' as date) - INTERVAL '730 days'
    AND u.LastAccessDate >= cast('2024-10-01' as date) - INTERVAL '30 days'
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
    AND p.CreationDate >= cast('2024-10-01' as date) - INTERVAL '24 months'
  GROUP BY DATE_TRUNC('month', p.CreationDate)
),
user_engagement AS (
  SELECT
    u.Id AS user_id,
    u.DisplayName,
    COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 END) AS edits_made,
    COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS upvotes_cast,
    COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS downvotes_cast,
    AVG(DATE_PART('day', p.LastActivityDate - p.CreationDate)) AS avg_post_age_days
  FROM Users u
  JOIN Posts p ON u.Id = p.OwnerUserId OR u.Id = p.LastEditorUserId
  LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.UserId = u.Id
  LEFT JOIN Votes v ON p.Id = v.PostId AND v.UserId = u.Id
  WHERE u.Reputation > 100
    AND p.CreationDate >= cast('2024-10-01' as date) - INTERVAL '365 days'
  GROUP BY u.Id, u.DisplayName
  HAVING COUNT(p.Id) >= 5
),
ue_final AS (
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
LEFT JOIN ue_final ue ON TRUE
WHERE ms.month >= cast('2024-10-01' as date) - INTERVAL '12 months'
  AND EXISTS (
    SELECT 1
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= ms.month
      AND p.CreationDate < ms.month + INTERVAL '1 month'
      AND POSITION(pt.TagName IN p.Tags) > 0
  )
ORDER BY pt.TagName, ms.month DESC, ms.total_views DESC
LIMIT 1000;