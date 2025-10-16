-- {"query": "21061.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2168, "output_tokens": 1841} 

WITH user_activity AS (
  SELECT 
    u.Id AS user_id,
    u.Reputation,
    u.CreationDate AS user_creation,
    COUNT(DISTINCT p.Id) AS post_count,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS question_count,
    SUM(p.Score) AS total_score,
    AVG(p.ViewCount) AS avg_view_count,
    ROW_NUMBER() OVER (PARTITION BY EXTRACT(YEAR FROM p.CreationDate) ORDER BY COUNT(DISTINCT p.Id) DESC) AS yearly_post_rank,
    LAG(u.Reputation) OVER (PARTITION BY u.Id ORDER BY u.CreationDate) AS prev_reputation
  FROM Users u
  LEFT JOIN Posts p ON u.Id = p.OwnerUserId 
    AND p.PostTypeId IN (1, 2) 
    AND p.CreationDate >= u.CreationDate 
    AND p.CreationDate < u.CreationDate + INTERVAL '1 year'
  WHERE u.Reputation >= 100 
    AND u.CreationDate >= CURRENT_DATE - INTERVAL '5 years'
  GROUP BY u.Id, u.Reputation, u.CreationDate
  HAVING COUNT(DISTINCT p.Id) > 0
),
detailed_posts AS (
  SELECT 
    p.Id AS post_id,
    p.OwnerUserId,
    p.PostTypeId,
    p.Title,
    p.CreationDate AS post_date,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    COALESCE(p.AnswerCount, 0) AS answer_count,
    CASE 
      WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1 
      ELSE 0 
    END AS has_accepted,
    LENGTH(p.Body) AS body_length,
    CASE 
      WHEN p.Tags IS NOT NULL AND p.Tags != '' 
      THEN CARDINALITY(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><')) 
      ELSE 0 
    END AS tag_count,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId, EXTRACT(MONTH FROM p.CreationDate) ORDER BY p.Score DESC) AS monthly_score_rank
  FROM Posts p
  WHERE p.PostTypeId IN (1, 2)
    AND p.DeletionDate IS NULL
    AND (p.ClosedDate IS NULL OR p.ClosedDate > p.CreationDate)
),
post_with_comments AS (
  SELECT 
    dp.post_id,
    dp.OwnerUserId,
    dp.PostTypeId,
    dp.Title,
    dp.post_date,
    dp.Score AS post_score,
    dp.ViewCount,
    dp.CommentCount,
    dp.answer_count,
    dp.has_accepted,
    dp.body_length,
    dp.tag_count,
    dp.monthly_score_rank,
    COUNT(c.Id) AS actual_comment_count,
    AVG(LENGTH(c.Text)) AS avg_comment_length,
    STRING_AGG(SUBSTRING(c.Text, 1, 50), ' || ') AS comment_preview,
    (SELECT COUNT(DISTINCT v.UserId) 
     FROM Votes v 
     WHERE v.PostId = dp.post_id 
       AND v.VoteTypeId IN (2, 3) 
       AND v.CreationDate BETWEEN dp.post_date - INTERVAL '1 day' AND dp.post_date + INTERVAL '1 day'
    ) AS recent_voter_count
  FROM detailed_posts dp
  LEFT JOIN Comments c ON c.PostId = dp.post_id 
    AND c.Score >= 0
    AND c.CreationDate <= dp.post_date + INTERVAL '7 days'
  GROUP BY 
    dp.post_id, dp.OwnerUserId, dp.PostTypeId, dp.Title, dp.post_date, 
    dp.Score, dp.ViewCount, dp.CommentCount, dp.answer_count, 
    dp.has_accepted, dp.body_length, dp.tag_count, dp.monthly_score_rank
  HAVING COUNT(c.Id) > 0 OR dp.CommentCount > 0
),
complex_stats AS (
  SELECT 
    ua.user_id,
    ua.post_count,
    ua.question_count,
    ua.total_score,
    ua.avg_view_count,
    ua.yearly_post_rank,
    pwc.post_score,
    pwc.ViewCount,
    pwc.answer_count,
    pwc.has_accepted,
    pwc.actual_comment_count,
    CASE 
      WHEN pwc.body_length > 1000 THEN 'Long'
      WHEN pwc.body_length > 200 THEN 'Medium'
      ELSE 'Short'
    END AS post_length_category,
    pwc.tag_count,
    pwc.monthly_score_rank,
    (pwc.post_score * 1.0 / NULLIF(pwc.ViewCount, 0)) AS score_per_view,
    GREATEST(0, pwc.ViewCount - LAG(pwc.ViewCount) OVER (PARTITION BY pwc.OwnerUserId ORDER BY pwc.post_date)) AS view_growth,
    ROW_NUMBER() OVER (PARTITION BY EXTRACT(YEAR FROM pwc.post_date) ORDER BY pwc.post_score DESC NULLS LAST) AS yearly_post_score_rank,
    DENSE_RANK() OVER (ORDER BY ua.total_score DESC) AS overall_user_rank
  FROM user_activity ua
  INNER JOIN post_with_comments pwc ON ua.user_id = pwc.OwnerUserId
    AND pwc.post_date >= ua.user_creation
    AND pwc.monthly_score_rank <= 3
  WHERE ua.yearly_post_rank <= 10
    OR (ua.question_count >= 5 AND pwc.PostTypeId = 1)
)
SELECT 
  cs.user_id,
  u.DisplayName,
  u.Location,
  cs.post_count,
  cs.question_count,
  cs.total_score,
  ROUND(cs.avg_view_count, 2) AS avg_views,
  cs.yearly_post_rank,
  cs.PostTypeId,
  SUBSTRING(cs.Title, 1, 100) AS title_preview,
  cs.post_date,
  cs.post_score,
  cs.ViewCount,
  cs.answer_count,
  cs.has_accepted,
  cs.actual_comment_count,
  cs.post_length_category,
  cs.tag_count,
  cs.monthly_score_rank,
  ROUND(cs.score_per_view, 4) AS score_per_view_ratio,
  cs.view_growth,
  cs.yearly_post_score_rank,
  cs.overall_user_rank,
  CASE 
    WHEN b.Name IS NOT NULL THEN b.Name
    ELSE 'No Special Badge'
  END AS top_badge,
  (SELECT STRING_AGG(t.TagName, ', ') 
   FROM Tags t 
   WHERE t.ExcerptPostId IS NOT NULL 
     AND t.Count > 100
   LIMIT 5
  ) AS popular_tags_sample
FROM complex_stats cs
INNER JOIN Users u ON cs.user_id = u.Id
LEFT JOIN (
  SELECT 
    ba.UserId,
    ba.Name,
    ROW_NUMBER() OVER (PARTITION BY ba.UserId ORDER BY ba.Date DESC) AS rn
  FROM Badges ba
  WHERE ba.Class = 1  -- Gold badges only
) b ON cs.user_id = b.UserId AND b.rn = 1
WHERE cs.overall_user_rank <= 50
  AND (cs.view_growth > 1000 OR cs.post_score >= 10)
  AND (u.Location IS NULL OR u.Location NOT LIKE '%spam%')
  AND NOT EXISTS (
    SELECT 1 FROM PostHistory ph 
    WHERE ph.PostId = cs.post_id 
      AND ph.PostHistoryTypeId = 12  -- Deleted
      AND ph.CreationDate > cs.post_date
  )
UNION ALL
SELECT 
  NULL AS user_id,
  'Community Aggregate' AS DisplayName,
  'Global' AS Location,
  SUM(cs.post_count) AS post_count,
  SUM(cs.question_count) AS question_count,
  SUM(cs.total_score) AS total_score,
  AVG(cs.avg_view_count) AS avg_views,
  NULL AS yearly_post_rank,
  NULL AS PostTypeId,
  NULL AS title_preview,
  CURRENT_DATE AS post_date,
  AVG(cs.post_score) AS post_score,
  AVG(cs.ViewCount) AS ViewCount,
  AVG(cs.answer_count) AS answer_count,
  AVG(cs.has_accepted) AS has_accepted,
  AVG(cs.actual_comment_count) AS actual_comment_count,
  'Aggregate' AS post_length_category,
  AVG(cs.tag_count) AS tag_count,
  NULL AS monthly_score_rank,
  AVG(cs.score_per_view) AS score_per_view_ratio,
  NULL AS view_growth,
  NULL AS yearly_post_score_rank,
  0 AS overall_user_rank,
  NULL AS top_badge,
  NULL AS popular_tags_sample
FROM complex_stats cs
ORDER BY overall_user_rank, post_score DESC NULLS LAST
LIMIT 100;
