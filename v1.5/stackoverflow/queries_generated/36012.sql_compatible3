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
  p.Tags,
  pc.CommentsToday,
  COALESCE(vs.Upvotes, 0) AS UpvotesToday,
  COALESCE(vs.Downvotes, 0) AS DownvotesToday,
  COALESCE(br.BadgeCount, 0) AS BadgeCountToday
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN (
  SELECT
    PostId,
    COUNT(*) AS CommentsToday
  FROM Comments
  WHERE CreationDate >= date_trunc('day', CAST('2024-10-01' AS DATE))
  GROUP BY PostId
) AS pc ON pc.PostId = p.Id
LEFT JOIN (
  SELECT
    PostId,
    SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
    SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes
  FROM Votes
  WHERE CreationDate >= date_trunc('day', CAST('2024-10-01' AS DATE))
  GROUP BY PostId
) AS vs ON vs.PostId = p.Id
LEFT JOIN (
  SELECT
    OwnerUserId,
    COUNT(*) AS BadgeCount
  FROM Badges
  WHERE Date >= date_trunc('day', CAST('2024-10-01' AS DATE))
  GROUP BY OwnerUserId
) AS br ON br.OwnerUserId = p.OwnerUserId
WHERE
  p.CreationDate >= date_trunc('day', CAST('2024-10-01' AS DATE)) - INTERVAL '7 days'
  AND p.PostTypeId IN (1, 2)
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
  p.Tags,
  pc.CommentsToday,
  vs.Upvotes,
  vs.Downvotes,
  br.BadgeCount
ORDER BY
  p.CreationDate DESC
LIMIT 100;