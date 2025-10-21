-- {"query": "36009.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 423} 
SELECT
  p.Id AS PostId,
  p.Title,
  p.PostTypeId,
  p.CreationDate,
  p.ViewCount,
  p.Score,
  p.OwnerUserId,
  u.Reputation,
  u.CreationDate AS UserCreationDate,
  u.Location,
  p.Tags,
  ARRAY_AGG(DISTINCT t.Name) AS involved_tag_names,
  COALESCE(vc.TotalVotes, 0) AS TotalVotes,
  COALESCE(ba.TotalBadges, 0) AS BadgeCount,
  COALESCE(cl.ClosedCount, 0) AS ClosedCount,
  p.AnswerCount,
  p.CommentCount
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN LATERAL (
  SELECT SUM(CASE WHEN V.VoteTypeId IN (2,3,16) THEN 1 ELSE 0 END) AS TotalVotes
  FROM Votes V
  WHERE V.PostId = p.Id
) vc ON true
LEFT JOIN (
  SELECT UserId, COUNT(*) AS TotalBadges
  FROM Badges
  GROUP BY UserId
) ba ON ba.UserId = p.OwnerUserId
LEFT JOIN (
  SELECT PostId, COUNT(*) AS ClosedCount
  FROM PostHistory ph
  WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 10
  GROUP BY ph.PostId
) cl ON cl.PostId = p.Id
WHERE p.PostTypeId = 1 -- questions
  AND p.CreationDate >= NOW() - INTERVAL '180 days'
GROUP BY
  p.Id, p.Title, p.PostTypeId, p.CreationDate, p.ViewCount, p.Score,
  p.OwnerUserId, u.Reputation, u.CreationDate, u.Location, p.Tags,
  p.AnswerCount, p.CommentCount, vc.TotalVotes, ba.TotalBadges, cl.ClosedCount
ORDER BY p.Score DESC
LIMIT 100;