SELECT
  p.Id AS PostId,
  p.Title,
  p.PostTypeId,
  p.CreationDate,
  p.ViewCount,
  p.Score,
  p.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation,
  t.Tag AS Tags,
  COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS Upvotes,
  COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS Downvotes,
  AVG(COALESCE(v.BountyAmount, 0)) AS AvgBounty
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.PostId = p.Id
LEFT JOIN LATERAL (
  SELECT unnest(string_to_array(substr(p.Tags, 2, length(p.Tags) - 2), '><')) AS Tag
) t ON TRUE
GROUP BY
  p.Id,
  p.Title,
  p.PostTypeId,
  p.CreationDate,
  p.ViewCount,
  p.Score,
  p.OwnerUserId,
  u.DisplayName,
  u.Reputation,
  t.Tag
ORDER BY
  p.CreationDate DESC
LIMIT 1000;