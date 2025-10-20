-- {"query": "36032.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 333} 
SELECT
  p.Id AS PostId,
  p.Title,
  p.PostTypeId,
  p.CreationDate,
  p.Score,
  p.ViewCount,
  p.AnswerCount,
  p.CommentCount,
  p.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation,
  u.CreationDate AS OwnerCreationDate,
  u.Views,
  u.UpVotes,
  u.DownVotes,
  v.VoteCount,
  vt.Name AS MostRecentVoteType,
  COALESCE(p.Tags, '') AS Tags,
  COALESCE(pt.Name, '') AS PostTypeName,
  COALESCE(p.AcceptedAnswerId, 0) AS AcceptedAnswerId,
  COALESCE(p.LastActivityDate, p.CreationDate) AS LastActivityDate
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN (
  SELECT PostId, COUNT(*) AS VoteCount
  FROM Votes
  GROUP BY PostId
) v ON p.Id = v.PostId
LEFT JOIN VoteTypes vt ON (
  SELECT VoteTypeId
  FROM Votes
  WHERE PostId = p.Id
  ORDER BY CreationDate DESC
  LIMIT 1
) = vt.Id
LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
WHERE p.CreationDate >= NOW() - INTERVAL '180 days'
  AND (p.PostTypeId = 1 OR p.PostTypeId = 2)
ORDER BY p.Score DESC, p.CreationDate DESC
LIMIT 100;