SELECT
  p.OwnerUserId AS OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  COUNT(*) AS TotalPosts,
  SUM(p.Score) AS SumScore,
  AVG(p.Score) AS AvgScore,
  MAX(p.LastActivityDate) AS LastActive,
  MIN(p.CreationDate) AS CreatedEarliest,
  STRING_AGG(DISTINCT vvt.Name, ',') FILTER (WHERE vtt.Name = 'UpMod') AS UpvotesByType,
  CASE
    WHEN SUM(CASE WHEN v.Name = 'Helpful' THEN 1 ELSE 0 END) > 0 THEN SUM(CASE WHEN v.Name = 'Helpful' THEN 1 ELSE 0 END)
    ELSE 0
  END AS HelpfulVotes
FROM
  Posts p
  INNER JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN VoteTypes vtt ON 1=1
  LEFT JOIN (
    SELECT v.PostId, v.VoteTypeId, v.UserId, v.CreationDate, vt.Name
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  ) v ON p.Id = v.PostId
  LEFT JOIN VoteTypes vvt ON v.VoteTypeId = vvt.Id
  LEFT JOIN Users up ON up.Id = p.OwnerUserId
WHERE
  p.PostTypeId = 1
  AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
GROUP BY
  p.OwnerUserId,
  u.DisplayName,
  p.OwnerUserId
HAVING
  COUNT(*) > 0
ORDER BY
  TotalPosts DESC,
  LastActive DESC
LIMIT 100;