-- {"query": "36051.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 333} 
SELECT
  p.Id AS PostId,
  p.Title,
  p.PostTypeId,
  p.CreationDate,
  p.Score,
  p.ViewCount,
  p.Tags,
  p.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  COALESCE(a.Id, 0) AS AcceptedAnswerId,
  a.Title AS AcceptedAnswerTitle,
  p.CommentCount,
  p.AnswerCount,
  COUNT(DISTINCT v.Id) AS TotalVotes,
  AVG(v.BountyAmount) FILTER (WHERE v.BountyAmount IS NOT NULL) AS AvgBounty,
  MAX(v.CreationDate) AS LastVoteDate,
  pc.Count AS CommentCountByPost
FROM
  Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Posts a ON p.AcceptedAnswerId = a.Id
LEFT JOIN (
  SELECT PostId, COUNT(*) AS Count
  FROM Comments
  GROUP BY PostId
) pc ON p.Id = pc.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
WHERE
  p.PostTypeId = 1 -- questions
  AND p.CreationDate >= NOW() - INTERVAL '1 year'
GROUP BY
  p.Id, p.Title, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount,
  p.Tags, p.OwnerUserId, u.DisplayName, a.Id, a.Title, p.CommentCount, p.AnswerCount, pc.Count
ORDER BY
  p.CreationDate DESC
LIMIT 100;