-- {"query": "36078.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 304} 
SELECT
  p.Id AS PostId,
  p.Title,
  p.PostTypeId,
  p.CreationDate,
  p.ViewCount,
  p.Score,
  p.OwnerDisplayName,
  p.Tags,
  ARRAY_AGG(DISTINCT tp.Name) AS PostTypeNames,
  COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS Upvotes,
  COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS Downvotes,
  COUNT(DISTINCT c.Id) AS CommentCount,
  AVG(NULLIF(v.BountyAmount, 0)) FILTER (WHERE v.VoteTypeId = 8 OR v.VoteTypeId = 9) AS AverageBountyOnVotes,
  MIN(p.CreationDate) OVER () AS BenchmarkStartTime,
  MAX(p.LastActivityDate) OVER () AS BenchmarkEndTime
FROM
  Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN PostTypes pt ON pt.Id = p.PostTypeId
  LEFT JOIN (
    SELECT DISTINCT Id, Name
    FROM PostHistoryTypes
  ) AS tp ON TRUE
GROUP BY
  p.Id, p.Title, p.PostTypeId, p.CreationDate, p.ViewCount, p.Score, p.OwnerDisplayName, p.Tags
ORDER BY
  p.CreationDate DESC
LIMIT 100;