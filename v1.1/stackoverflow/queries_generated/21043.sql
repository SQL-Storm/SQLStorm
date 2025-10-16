-- {"query": "21043.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2168, "output_tokens": 1290} 

WITH active_users AS (
  SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS post_count,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS question_count,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS answer_count,
    AVG(u.Reputation * 1.0) OVER (PARTITION BY SUBSTRING(u.Location, 1, 20)) AS avg_reputation_by_location_prefix
  FROM Users u
  INNER JOIN Posts p ON u.Id = p.OwnerUserId
  WHERE u.Reputation > 100 
    AND u.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
    AND u.Location IS NOT NULL 
    AND LENGTH(TRIM(u.Location)) > 0
  GROUP BY u.Id, u.DisplayName, u.Reputation, SUBSTRING(u.Location, 1, 20)
  HAVING COUNT(DISTINCT p.Id) >= 5
),
recent_posts_with_stats AS (
  SELECT 
    p.Id,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.ClosedDate,
    COALESCE(p.Tags, '') AS tags,
    au.post_count,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.ViewCount DESC, p.Score DESC) AS view_rank,
    LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS prev_post_score,
    LEAD(p.Title) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS next_post_title,
    CASE 
      WHEN p.ClosedDate IS NOT NULL THEN 
        CONCAT('Closed: ', EXTRACT(DAY FROM (CURRENT_DATE - p.ClosedDate)), ' days ago')
      WHEN p.CommunityOwnedDate IS NOT NULL THEN 
        CONCAT('Community: ', UPPER(SUBSTRING(p.OwnerDisplayName, 1, 1)), LOWER(SUBSTRING(p.OwnerDisplayName, 2)))
      ELSE 'Active'
    END AS post_status
  FROM Posts p
  LEFT JOIN active_users au ON p.OwnerUserId = au.Id
  WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
    AND (p.PostTypeId IN (1, 2) OR (p.PostTypeId = 4 AND p.Title IS NOT NULL))
),
aggregated_badges AS (
  SELECT 
    b.UserId,
    STRING_AGG(DISTINCT b.Name, ' | ' ORDER BY b.Date DESC) AS badge_names,
    COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS gold_count,
    COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS silver_count,
    COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS bronze_count,
    MAX(b.Date) AS latest_badge_date
  FROM Badges b
  WHERE b.Date >= CURRENT_DATE - INTERVAL '6 months'
  GROUP BY b.UserId
)
SELECT 
  rps.Title,
  rps.CreationDate,
  rps.Score,
  rps.ViewCount,
  rps.view_rank,
  rps.post_status,
  au.DisplayName AS owner_name,
  au.question_count,
  au.answer_count,
  COALESCE(ab.badge_names, 'No recent badges') AS recent_badges,
  ab.gold_count,
  (rps.Score - COALESCE(rps.prev_post_score, 0)) AS score_improvement,
  CASE 
    WHEN rps.tags ~* 'sql|database' THEN 'Tech-focused'
    WHEN LENGTH(rps.Title) > 80 THEN 'Long title'
    WHEN rps.ClosedDate IS NOT NULL AND rps.Score < 0 THEN 'Controversial closed'
    ELSE 'Standard'
  END AS post_category,
  CASE 
    WHEN rps.AnswerCount > au.answer_count * 0.5 THEN 'High response rate'
    WHEN rps.ViewCount IS NULL OR rps.ViewCount = 0 THEN NULL
    ELSE 'Normal'
  END AS engagement_flag
FROM recent_posts_with_stats rps
INNER JOIN active_users au ON rps.OwnerUserId = au.Id
LEFT JOIN aggregated_badges ab ON au.Id = ab.UserId
LEFT JOIN (
  SELECT 
    pl.PostId,
    COUNT(DISTINCT pl.RelatedPostId) AS link_count,
    STRING_AGG(DISTINCT lt.Name, ', ' ORDER BY pl.CreationDate) AS link_types
  FROM PostLinks pl
  INNER JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  WHERE pl.CreationDate >= CURRENT_DATE - INTERVAL '3 months'
    AND lt.Name IN ('Linked', 'Duplicate')
  GROUP BY pl.PostId
  HAVING COUNT(DISTINCT pl.RelatedPostId) > 0
) links ON rps.Id = links.PostId
WHERE rps.view_rank <= 50
  AND (rps.Score > 0 OR rps.ClosedDate IS NOT NULL)
  AND au.Location ILIKE ANY (ARRAY['%USA%', '%UK%', '%Canada%', '%Australia%'])
UNION ALL
SELECT 
  NULL AS Title,
  CURRENT_DATE AS CreationDate,
  0 AS Score,
  0 AS ViewCount,
  NULL AS view_rank,
  'Summary Row' AS post_status,
  'AGGREGATE' AS owner_name,
  SUM(au.question_count) AS question_count,
  SUM(au.answer_count) AS answer_count,
  'Total Stats' AS recent_badges,
  SUM(COALESCE(ab.gold_count, 0)) AS gold_count,
  NULL AS score_improvement,
  'Summary' AS post_category,
  NULL AS engagement_flag
FROM active_users au
LEFT JOIN aggregated_badges ab ON au.Id = ab.UserId
WHERE au.Reputation >= 1000
ORDER BY 
  CASE WHEN Title IS NULL THEN 0 ELSE 1 END,
  ViewCount DESC NULLS LAST,
  CreationDate DESC;
