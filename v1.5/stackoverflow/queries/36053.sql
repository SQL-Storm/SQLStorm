-- {"query": "36053.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 373} 
SELECT
  p.Id AS PostId,
  p.Title,
  p.PostTypeId,
  p.CreationDate,
  p.ViewCount,
  p.Score,
  p.OwnerUserId,
  p.Tags,
  p.AnswerCount,
  p.CommentCount,
  p.FavoriteCount,
  pt.Name AS PostTypeName,
  u.Reputation,
  u.CreationDate AS UserCreationDate,
  u.DisplayName AS UserDisplayName,
  COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesReceived,
  COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotesReceived,
  COUNT(DISTINCT c.Id) AS CommentCountTotal,
  COUNT(DISTINCT a.Id) AS AnswerCountTotal,
  AVG(CASE WHEN v.VoteTypeId = 2 THEN v.BountyAmount END) AS AvgUpvoteBounty,
  MAX(p.LastActivityDate) AS LastActivity
FROM Posts p
JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.PostId = p.Id
LEFT JOIN Comments c ON c.PostId = p.Id
LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
GROUP BY
  p.Id, p.Title, p.PostTypeId, p.CreationDate, p.ViewCount, p.Score,
  p.OwnerUserId, p.Tags, p.AnswerCount, p.CommentCount, p.FavoriteCount,
  pt.Name, u.Reputation, u.CreationDate, u.DisplayName
ORDER BY
  p.CreationDate DESC
LIMIT 100;