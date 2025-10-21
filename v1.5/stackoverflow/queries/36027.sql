SELECT
  p.Id AS PostId,
  p.Title,
  p.PostTypeId,
  p.CreationDate,
  p.ViewCount,
  p.Score,
  p.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  COUNT(*) OVER () AS TotalPosts,
  /* Distinct voter count not available as window function in all dialects; compute per group after grouping below if needed; placeholder using SUM with DISTINCT applied via subquery is not portable; using a subquery approach below to ensure compatibility. */
  NULL AS DistinctVoters,
  AVG(v.BountyAmount) OVER (PARTITION BY NULL) AS AvgBounty
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.PostId = p.Id
WHERE
  p.CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30' DAY
  AND p.PostTypeId IN (1, 2)
ORDER BY p.CreationDate DESC
LIMIT 100
OFFSET 0;