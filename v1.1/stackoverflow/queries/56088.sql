WITH top_voters AS (
  SELECT u.Id, u.DisplayName, COUNT(v.Id) AS vote_count
  FROM Users u
  JOIN Votes v ON u.Id = v.UserId
  WHERE v.VoteTypeId IN (2, 3)
  GROUP BY u.Id, u.DisplayName
  ORDER BY vote_count DESC
  LIMIT 100
),
top_posts AS (
  SELECT p.Id, p.Title, p.Score, COUNT(c.Id) AS comment_count
  FROM Posts p
  JOIN Comments c ON p.Id = c.PostId
  GROUP BY p.Id, p.Title, p.Score
  ORDER BY comment_count DESC
  LIMIT 100
),
post_history_stats AS (
  SELECT ph.PostId, COUNT(ph.Id) AS revision_count, SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS close_count
  FROM PostHistory ph
  GROUP BY ph.PostId
)
SELECT 
  u.DisplayName, 
  u.Reputation, 
  tv.vote_count, 
  p.Title, 
  p.Score, 
  tp.comment_count, 
  phs.revision_count, 
  phs.close_count
FROM Users u
JOIN top_voters tv ON u.Id = tv.Id
JOIN Posts p ON u.Id = p.OwnerUserId
JOIN top_posts tp ON p.Id = tp.Id
JOIN post_history_stats phs ON p.Id = phs.PostId
GROUP BY
  u.DisplayName,
  u.Reputation,
  tv.vote_count,
  p.Title,
  p.Score,
  tp.comment_count,
  phs.revision_count,
  phs.close_count
ORDER BY tv.vote_count DESC, phs.revision_count DESC;