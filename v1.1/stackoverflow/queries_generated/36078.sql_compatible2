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
  COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS Upvotes,
  COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS Downvotes,
  COUNT(DISTINCT c.Id) AS CommentCount,
  AVG(NULLIF(CASE WHEN v.VoteTypeId IN (8,9) THEN v.BountyAmount END, 0)) AS AverageBountyOnVotes,
  MIN(p.CreationDate) AS BenchmarkStartTime,
  MAX(p.LastActivityDate) AS BenchmarkEndTime
FROM
  Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN PostTypes pt ON pt.Id = p.PostTypeId
  LEFT JOIN (
    SELECT DISTINCT Id, Name
    FROM PostHistoryTypes
  ) tp ON TRUE
  LEFT JOIN Comments c ON c.PostId = p.Id
GROUP BY
  p.Id,
  p.Title,
  p.PostTypeId,
  p.CreationDate,
  p.ViewCount,
  p.Score,
  p.OwnerDisplayName,
  p.Tags
ORDER BY
  p.CreationDate DESC
LIMIT 100;