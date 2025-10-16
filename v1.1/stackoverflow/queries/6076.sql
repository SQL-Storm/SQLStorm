SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  COUNT(DISTINCT p.Id) AS PostsCreated,
  AVG(CASE WHEN v.VoteTypeId = 2 THEN v.BountyAmount * 0.0 + 1 ELSE NULL END) AS AvgUpvotesPerPost,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived,
  MAX(p.CreationDate) AS LastPostDate,
  MAX(CASE WHEN b.Id IS NOT NULL THEN b.Date ELSE NULL END) AS LastBadgeDate
FROM
  Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.PostId = p.Id
  AND v.VoteTypeId IN (2,3)
LEFT JOIN Badges b ON b.UserId = u.Id
  AND b.Date = (
    SELECT MAX(b2.Date) FROM Badges b2 WHERE b2.UserId = u.Id
  )
GROUP BY
  u.Id, u.DisplayName, u.Reputation
HAVING
  COUNT(DISTINCT p.Id) > 0
ORDER BY
  u.Reputation DESC, u.Id;