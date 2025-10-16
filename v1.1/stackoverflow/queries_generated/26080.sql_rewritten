-- {"query": "26080.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 499} 
WITH top_users AS (
  SELECT u.Id, u.DisplayName, COUNT(DISTINCT p.Id) AS post_count
  FROM Users u
  JOIN Posts p ON u.Id = p.OwnerUserId
  GROUP BY u.Id, u.DisplayName
  HAVING COUNT(DISTINCT p.Id) > 100
),
top_posts AS (
  SELECT p.Id, p.Title, p.Score, p.ViewCount,
         ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS score_rank,
         ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC) AS view_rank
  FROM Posts p
  WHERE p.PostTypeId = 1 AND p.Score > 0
),
user_badges AS (
  SELECT u.Id, COUNT(DISTINCT b.Name) AS badge_count
  FROM Users u
  JOIN Badges b ON u.Id = b.UserId
  GROUP BY u.Id
)
SELECT 
  tu.DisplayName, 
  tu.post_count, 
  ub.badge_count, 
  tp.Title, 
  tp.Score, 
  tp.ViewCount, 
  tp.score_rank, 
  tp.view_rank,
  ph.Comment,
  COALESCE(ph.Text, '') AS post_history_text,
  COALESCE(v.VoteTypeId, 0) AS vote_type_id,
  COALESCE(pl.LinkTypeId, 0) AS link_type_id,
  CASE 
    WHEN t.TagName IS NOT NULL THEN t.TagName
    ELSE 'Unknown'
  END AS tag_name,
  ph.PostHistoryTypeId,
  ph.UserId,
  ph.CreationDate,
  ph.PostId,
  ph.UserDisplayName
FROM top_users tu
JOIN user_badges ub ON tu.Id = ub.Id
JOIN Posts p ON tu.Id = p.OwnerUserId
JOIN top_posts tp ON p.Id = tp.Id
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
LEFT JOIN Tags t ON p.Id = t.ExcerptPostId
WHERE ph.PostHistoryTypeId IN (10, 11, 12, 13)
  AND v.VoteTypeId IN (1, 2, 3)
  AND pl.LinkTypeId IN (1, 3)
  AND t.TagName IS NOT NULL
ORDER BY tu.post_count DESC, tp.score_rank, tp.view_rank;