WITH top_users AS (
  SELECT u.Id, u.DisplayName, COUNT(b.Id) AS badge_count
  FROM Users u
  JOIN Badges b ON u.Id = b.UserId
  GROUP BY u.Id, u.DisplayName
  ORDER BY badge_count DESC
  LIMIT 100
),
top_posts AS (
  SELECT p.Id, p.Title, p.Score, p.ViewCount,
    ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS score_rank,
    ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC) AS view_rank
  FROM Posts p
  WHERE p.PostTypeId = 1 AND p.Score > 0
),
linked_posts AS (
  SELECT pl.PostId, pl.RelatedPostId,
    ROW_NUMBER() OVER (PARTITION BY pl.PostId ORDER BY pl.CreationDate) AS link_rank
  FROM PostLinks pl
  WHERE pl.LinkTypeId = 1
)
SELECT 
  u.Id AS user_id,
  u.DisplayName AS user_name,
  p.Id AS post_id,
  p.Title AS post_title,
  p.Score AS post_score,
  p.ViewCount AS post_views,
  ph.PostHistoryTypeId AS post_history_type,
  ph.CreationDate AS post_history_date,
  ph.UserId AS post_history_user_id,
  ph.Comment AS post_history_comment,
  COALESCE(v.VoteTypeId, 0) AS vote_type,
  COALESCE(v.CreationDate, TIMESTAMP '2024-10-01 12:34:56') AS vote_date,
  COALESCE(lp.RelatedPostId, 0) AS linked_post_id,
  COALESCE(lp.link_rank, 0) AS linked_post_rank,
  COALESCE(tu.badge_count, 0) AS user_badge_count,
  tp.score_rank,
  tp.view_rank,
  CASE 
    WHEN p.Score > 100 THEN 'High Score'
    WHEN p.Score > 50 THEN 'Medium Score'
    ELSE 'Low Score'
  END AS score_category,
  CASE 
    WHEN p.ViewCount > 1000 THEN 'High Views'
    WHEN p.ViewCount > 500 THEN 'Medium Views'
    ELSE 'Low Views'
  END AS view_category,
  ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS overall_rank
FROM Users u
JOIN Posts p ON u.Id = p.OwnerUserId
JOIN PostHistory ph ON p.Id = ph.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN linked_posts lp ON p.Id = lp.PostId
LEFT JOIN top_users tu ON u.Id = tu.Id
LEFT JOIN top_posts tp ON p.Id = tp.Id
WHERE p.PostTypeId = 1
  AND p.Score > 0
  AND ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15)
  AND (v.VoteTypeId IS NULL OR v.VoteTypeId IN (1, 2, 3))
  AND (lp.link_rank IS NULL OR lp.link_rank = 1)
GROUP BY
  u.Id,
  u.DisplayName,
  p.Id,
  p.Title,
  p.Score,
  p.ViewCount,
  ph.PostHistoryTypeId,
  ph.CreationDate,
  ph.UserId,
  ph.Comment,
  v.VoteTypeId,
  v.CreationDate,
  lp.RelatedPostId,
  lp.link_rank,
  tu.badge_count,
  tp.score_rank,
  tp.view_rank
ORDER BY p.Score DESC, p.ViewCount DESC;