SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  COUNT(DISTINCT p.Id) AS PostsCreated,
  COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpvotesGiven,
  COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownvotesGiven,
  AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
  SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS TotalQuestionViews,
  MAX(p.CreationDate) AS LastPostDate,
  SUM(CASE WHEN b.Id IS NOT NULL THEN 1 ELSE 0 END) AS BadgesEarned,
  STRING_AGG(DISTINCT t.Name, ',') AS TaggedByName
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.UserId = u.Id
    AND v.PostId = p.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN (
    SELECT
      b2.UserId,
      t.Name
    FROM Badges b2
      JOIN (SELECT DISTINCT Name FROM Badges) t ON t.Name = b2.Name
  ) AS t ON t.UserId = u.Id
WHERE
  u.CreationDate >= TIMESTAMP '2015-01-01 00:00:00'
  AND u.LastAccessDate <= TIMESTAMP '2024-12-31 23:59:59'
  AND (u.Location IS NULL OR u.Location <> '')
  AND NOT EXISTS (
    SELECT 1
    FROM Posts p2
    WHERE p2.OwnerUserId = u.Id
      AND p2.PostTypeId = 1
      AND p2.Title IS NULL
  )
GROUP BY
  u.Id,
  u.DisplayName,
  u.Reputation
HAVING
  COUNT(DISTINCT p.Id) > 0
ORDER BY
  Reputation DESC,
  LastPostDate DESC
OFFSET 0 ROWS
FETCH NEXT 100 ROWS ONLY;