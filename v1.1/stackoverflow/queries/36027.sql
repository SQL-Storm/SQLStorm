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
  dv.DistinctVoters,
  ab.AvgBounty
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.PostId = p.Id
LEFT JOIN (
  SELECT COUNT(DISTINCT UserId) AS DistinctVoters
  FROM Votes
) dv ON 1=1
LEFT JOIN (
  -- compute average bounty across all votes (exclude NULLs)
  SELECT AVG(BountyAmount) AS AvgBounty
  FROM Votes
  WHERE BountyAmount IS NOT NULL
) ab ON 1=1
WHERE
  p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY
  AND p.PostTypeId IN (1, 2)
GROUP BY
  p.Id, p.Title, p.PostTypeId, p.CreationDate, p.ViewCount, p.Score, p.OwnerUserId, u.DisplayName, dv.DistinctVoters, ab.AvgBounty
ORDER BY p.CreationDate DESC
LIMIT 100;