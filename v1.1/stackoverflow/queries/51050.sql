WITH top_users AS (
  SELECT u.Id AS user_id, u.Reputation, u.DisplayName,
         ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS rep_rank
  FROM Users u
  WHERE u.Reputation > 1000
),
top_tags AS (
  SELECT t.Id AS tag_id, t.TagName, t.Count,
         ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS tag_rank
  FROM Tags t
  WHERE t.Count > 500
),
user_activity AS (
  SELECT 
    tu.user_id,
    tu.Reputation,
    tu.DisplayName,
    COUNT(DISTINCT p.Id) AS post_count,
    SUM(p.ViewCount) AS total_views,
    AVG(p.Score) AS avg_score,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS question_count,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS answer_count,
    SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) AS positive_posts
  FROM top_users tu
  LEFT JOIN Posts p ON p.OwnerUserId = tu.user_id 
    AND p.PostTypeId IN (1, 2)
    AND p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '1 year'
  GROUP BY tu.user_id, tu.Reputation, tu.DisplayName
  HAVING COUNT(DISTINCT p.Id) > 10
),
tag_posts AS (
  SELECT 
    tt.tag_id,
    tt.TagName,
    tt.Count AS tag_usage,
    p.Id AS post_id,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.PostTypeId,
    p.OwnerUserId,
    ua.post_count AS user_activity_score
  FROM top_tags tt
  JOIN Posts p ON POSITION(tt.TagName IN p.Tags) > 0
    AND p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '2 years'
  LEFT JOIN user_activity ua ON ua.user_id = p.OwnerUserId
  WHERE ua.post_count IS NOT NULL
),
monthly_stats AS (
  SELECT 
    DATE_TRUNC('month', tp.CreationDate) AS month,
    tp.tag_id,
    tp.TagName,
    COUNT(DISTINCT tp.post_id) AS questions_per_month,
    AVG(tp.user_activity_score) AS avg_user_activity,
    SUM(tp.ViewCount) AS total_monthly_views,
    PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY tp.Score) AS p90_score
  FROM tag_posts tp
  GROUP BY DATE_TRUNC('month', tp.CreationDate), tp.tag_id, tp.TagName
)
SELECT 
  ms.month,
  ms.TagName,
  ms.questions_per_month,
  ms.total_monthly_views,
  ms.avg_user_activity,
  ms.p90_score,
  LAG(ms.questions_per_month) OVER (PARTITION BY ms.TagName ORDER BY ms.month) AS prev_month_questions,
  (ms.questions_per_month - LAG(ms.questions_per_month) OVER (PARTITION BY ms.TagName ORDER BY ms.month)) / 
    NULLIF(LAG(ms.questions_per_month) OVER (PARTITION BY ms.TagName ORDER BY ms.month), 0) * 100 AS growth_pct,
  RANK() OVER (PARTITION BY ms.month ORDER BY ms.total_monthly_views DESC) AS view_rank,
  (
    SELECT COUNT(DISTINCT b.UserId) 
    FROM Badges b 
    JOIN top_users tu ON b.UserId = tu.user_id
    WHERE tu.rep_rank <= 100
      AND b.Date >= ms.month 
      AND b.Date < ms.month + INTERVAL '1 month'
      AND b.Class = 1
  ) AS gold_badges_issued
FROM monthly_stats ms
WHERE ms.month >= CAST('2024-10-01' AS date) - INTERVAL '12 months'
  AND ms.questions_per_month > 5
ORDER BY ms.month DESC, ms.total_monthly_views DESC
LIMIT 100;