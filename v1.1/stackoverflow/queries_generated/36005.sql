-- {"query": "36005.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 443} 
SELECT
  p.Id AS PostId,
  p.PostTypeId,
  p.Title,
  p.CreationDate,
  p.Score,
  p.ViewCount,
  p.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation,
  p.Tags,
  pc.CommentCount,
  a.AnswerCount,
  COALESCE(b.TotalBadges, 0) AS BadgeCount,
  COALESCE(vv.VoteUp, 0) AS Upvotes,
  COALESCE(vv.VoteDown, 0) AS Downvotes,
  COALESCE(s.Saves, 0) AS Saves,
  COALESCE(cc.Comment, '') AS LastComment
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN (
  SELECT PostId, COUNT(*) AS AnswerCount
  FROM Posts
  WHERE PostTypeId = 2
  GROUP BY PostId
) a ON p.Id = a.PostId
LEFT JOIN (
  SELECT PostId, COUNT(*) AS CommentCount
  FROM Comments
  GROUP BY PostId
) pc ON p.Id = pc.PostId
LEFT JOIN (
  SELECT OwnerUserId, SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS VoteUp,
         SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS VoteDown
  FROM Votes
  GROUP BY OwnerUserId
) vv ON p.OwnerUserId = vv.OwnerUserId
LEFT JOIN (
  SELECT PostId, COUNT(*) AS Saves
  FROM Votes
  WHERE VoteTypeId = 5
  GROUP BY PostId
) s ON p.Id = s.PostId
LEFT JOIN (
  SELECT PostId, COUNT(*) AS TotalBadges
  FROM Badges
  GROUP BY PostId
) b ON p.Id = b.PostId
WHERE p.PostTypeId = 1
  AND p.CreationDate >= NOW() - INTERVAL '30 days'
ORDER BY p.Score DESC, p.ViewCount DESC
LIMIT 100;