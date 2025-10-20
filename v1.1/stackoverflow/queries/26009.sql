-- {"query": "26009.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 487} 
WITH top_users AS (
  SELECT u.Id, u.DisplayName, COUNT(DISTINCT p.Id) AS post_count
  FROM Users u
  JOIN Posts p ON u.Id = p.OwnerUserId
  GROUP BY u.Id, u.DisplayName
  ORDER BY post_count DESC
  LIMIT 10
),
top_posts AS (
  SELECT p.Id, p.Title, p.Score, p.ViewCount,
         ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC) AS row_num
  FROM Posts p
  WHERE p.PostTypeId = 1 AND p.Score > 0
),
post_history_stats AS (
  SELECT ph.PostId, COUNT(DISTINCT ph.PostHistoryTypeId) AS history_count,
         MAX(ph.CreationDate) AS last_edit_date
  FROM PostHistory ph
  GROUP BY ph.PostId
),
comment_counts AS (
  SELECT c.PostId, COUNT(c.Id) AS comment_count
  FROM Comments c
  GROUP BY c.PostId
),
votes_per_post AS (
  SELECT v.PostId, SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes
  FROM Votes v
  GROUP BY v.PostId
)
SELECT p.Id, p.Title, p.Score, p.ViewCount, tu.DisplayName AS top_user,
       phs.history_count, phs.last_edit_date, cc.comment_count,
       vpp.upvotes, vpp.downvotes,
       CASE WHEN p.Score > 0 AND p.ViewCount > 1000 THEN 'Highly viewed and scored'
            WHEN p.Score < 0 AND p.ViewCount < 100 THEN 'Lowly viewed and scored'
            ELSE 'Neutral' END AS post_status,
       ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC) AS post_rank
FROM Posts p
LEFT JOIN top_users tu ON p.OwnerUserId = tu.Id
LEFT JOIN post_history_stats phs ON p.Id = phs.PostId
LEFT JOIN comment_counts cc ON p.Id = cc.PostId
LEFT JOIN votes_per_post vpp ON p.Id = vpp.PostId
WHERE p.PostTypeId = 1 AND p.Score > 0 AND p.ViewCount > 100
ORDER BY p.ViewCount DESC;