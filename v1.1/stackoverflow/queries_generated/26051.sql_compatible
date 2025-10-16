WITH RECURSIVE post_hierarchy AS (
  SELECT Id, ParentId, 0 AS level
  FROM Posts
  WHERE ParentId IS NULL
  UNION ALL
  SELECT p.Id, p.ParentId, ph.level + 1
  FROM Posts p
  JOIN post_hierarchy ph ON p.ParentId = ph.Id
),
user_badge_count AS (
  SELECT UserId, COUNT(*) AS badge_count
  FROM Badges
  GROUP BY UserId
),
post_score AS (
  SELECT p.Id, SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) - SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS score
  FROM Posts p
  LEFT JOIN Votes v ON p.Id = v.PostId
  GROUP BY p.Id
)
SELECT 
  p.Id,
  p.Title,
  p.Score,
  p.ViewCount,
  p.AnswerCount,
  ph.level,
  ubc.badge_count,
  ps.score AS user_score,
  ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS row_num,
  LAG(p.Score, 1) OVER (ORDER BY p.Score DESC) AS prev_score,
  LEAD(p.Score, 1) OVER (ORDER BY p.Score DESC) AS next_score,
  CASE 
    WHEN p.Score > 0 THEN 'Positive'
    WHEN p.Score < 0 THEN 'Negative'
    ELSE 'Neutral'
  END AS score_type,
  CASE 
    WHEN EXISTS (SELECT 1 FROM PostLinks pl2 WHERE pl2.PostId = p.Id AND pl2.LinkTypeId = 1) THEN 'Linked'
    WHEN EXISTS (SELECT 1 FROM PostLinks pl3 WHERE pl3.PostId = p.Id AND pl3.LinkTypeId = 3) THEN 'Duplicate'
    ELSE 'None'
  END AS link_type,
  STRING_AGG(DISTINCT t.TagName, ', ') AS tags,
  MAX(COALESCE(u.Reputation, 0)) AS max_reputation,
  MIN(COALESCE(u.Reputation, 0)) AS min_reputation,
  AVG(COALESCE(u.Reputation, 0)) AS avg_reputation
FROM Posts p
LEFT JOIN post_hierarchy ph ON p.Id = ph.Id
LEFT JOIN user_badge_count ubc ON p.OwnerUserId = ubc.UserId
LEFT JOIN post_score ps ON p.Id = ps.Id
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
LEFT JOIN Tags t ON p.Id = t.ExcerptPostId OR p.Id = t.WikiPostId
LEFT JOIN Users u ON p.OwnerUserId = u.Id
GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, ph.level, ubc.badge_count, ps.score
HAVING p.Score > 0 AND p.ViewCount > 100 AND p.AnswerCount > 0
ORDER BY p.Score DESC
LIMIT 100;