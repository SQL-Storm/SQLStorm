WITH RECURSIVE post_hierarchy AS (
  SELECT Id, ParentId, 0 AS level
  FROM Posts
  WHERE ParentId IS NULL
  UNION ALL
  SELECT p.Id, p.ParentId, ph.level + 1
  FROM Posts p
  JOIN post_hierarchy ph ON p.ParentId = ph.Id
),
user_badges AS (
  SELECT u.Id, COUNT(DISTINCT b.Name) AS badge_count
  FROM Users u
  LEFT JOIN Badges b ON u.Id = b.UserId
  GROUP BY u.Id
),
post_votes AS (
  SELECT p.Id, SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) AS score
  FROM Posts p
  LEFT JOIN Votes v ON p.Id = v.PostId
  GROUP BY p.Id
),
tag_frequency AS (
  SELECT t.TagName, COUNT(p.Id) AS post_count
  FROM Tags t
  JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
  GROUP BY t.TagName
)
SELECT 
  p.Id,
  p.Title,
  p.Score,
  p.ViewCount,
  p.AnswerCount,
  p.CommentCount,
  p.FavoriteCount,
  ph.level,
  ub.badge_count,
  pv.score,
  tf.post_count,
  ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS row_num,
  LAG(p.Score, 1) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS prev_score,
  LEAD(p.Score, 1) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS next_score,
  SUM(p.Score) OVER (PARTITION BY p.PostTypeId) AS total_score,
  AVG(p.Score) OVER (PARTITION BY p.PostTypeId) AS avg_score,
  CASE 
    WHEN p.Score > (SELECT AVG(Score) FROM Posts) THEN 'High'
    WHEN p.Score < (SELECT AVG(Score) FROM Posts) THEN 'Low'
    ELSE 'Medium'
  END AS score_category,
  CASE 
    WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN 'Answered'
    WHEN p.PostTypeId = 1 AND p.AnswerCount = 0 THEN 'Unanswered'
    ELSE 'Not Applicable'
  END AS answer_status,
  COALESCE(pv.score, 0) AS vote_score,
  COALESCE(tf.post_count, 0) AS tag_count,
  COALESCE(ub.badge_count, 0) AS user_badge_count
FROM Posts p
JOIN post_hierarchy ph ON p.Id = ph.Id
LEFT JOIN user_badges ub ON p.OwnerUserId = ub.Id
LEFT JOIN post_votes pv ON p.Id = pv.Id
LEFT JOIN tag_frequency tf ON p.Tags LIKE '%' || tf.TagName || '%'
WHERE p.PostTypeId IN (1, 2)
  AND p.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
  AND p.Score > 0
  AND p.ViewCount > 100
ORDER BY p.CreationDate DESC;