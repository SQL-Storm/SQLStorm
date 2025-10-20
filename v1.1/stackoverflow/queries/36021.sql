-- {"query": "36021.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 351} 
SELECT
  p.Id AS PostId,
  p.Title,
  p.PostTypeId,
  p.CreationDate,
  p.Score,
  p.ViewCount,
  p.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  p.LastActivityDate,
  COUNT(DISTINCT v.Id) AS TotalVotes,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
  COUNT(DISTINCT c.Id) AS CommentCount,
  MAX(CASE WHEN v.VoteTypeId = 2 THEN v.CreationDate END) AS LastUpvoteDate,
  MAX(p.LastEditDate) AS LastEditDate,
  (SELECT COUNT(*) FROM Posts AS p2 WHERE p2.ParentId = p.Id) AS AnswerCount
FROM
  Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN Comments c ON c.PostId = p.Id
WHERE
  p.PostTypeId IN (1, 2) -- Questions and Answers
  AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days'
GROUP BY
  p.Id,
  p.Title,
  p.PostTypeId,
  p.CreationDate,
  p.Score,
  p.ViewCount,
  p.OwnerUserId,
  u.DisplayName,
  p.LastActivityDate
ORDER BY
  TOTALVOTES DESC,
  p.CreationDate DESC
LIMIT 100;