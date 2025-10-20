-- {"query": "36036.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 398} 
SELECT
  p.Id AS PostId,
  p.Title,
  p.PostTypeId,
  p.Score,
  p.ViewCount,
  p.CreationDate,
  p.LastActivityDate,
  p.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation,
  COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesReceived,
  COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotesReceived,
  ARRAY_AGG(DISTINCT t.Name) AS Tags,
  COUNT(c.Id) AS CommentCount,
  SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseVotes,
  SUM(CASE WHEN ph.PostHistoryTypeId = 16 THEN 1 ELSE 0 END) AS CommunityOwnedEvents
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.PostId = p.Id
LEFT JOIN (
  SELECT PostHistory.PostId, PostHistory.PostHistoryTypeId
  FROM PostHistory
) ph ON ph.PostId = p.Id
LEFT JOIN LATERAL (
  SELECT tg.Name
  FROM UNNEST(string_to_array(p.Tags, '><')) AS tg
) t ON TRUE
LEFT JOIN PostLinks pl ON pl.PostId = p.Id
LEFT JOIN Posts t2 ON t2.Id = pl.RelatedPostId
LEFT JOIN Tags t ON t.WikiPostId = p.Id OR t.ExcerptPostId = p.Id
GROUP BY
  p.Id,
  p.Title,
  p.PostTypeId,
  p.Score,
  p.ViewCount,
  p.CreationDate,
  p.LastActivityDate,
  p.OwnerUserId,
  u.DisplayName,
  u.Reputation
ORDER BY
  p.LastActivityDate DESC
LIMIT 100;