SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  u.Reputation,
  u.CreationDate AS UserCreationDate,
  u.LastAccessDate,
  COALESCE(u.Location, 'Unknown') AS Location,
  COUNT(DISTINCT p.Id) AS PostCount,
  AVG(p.Score) AS AvgPostScore,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
  COUNT(DISTINCT c.Id) AS CommentCount,
  MAX(p.LastActivityDate) AS LastActivity
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.UserId = u.Id
    AND v.VoteTypeId IN (2, 3)
  LEFT JOIN Comments c ON c.UserId = u.Id
WHERE
  u.Reputation > 1000
  AND (
    (u.CreationDate BETWEEN TIMESTAMP '2021-01-01 00:00:00' AND TIMESTAMP '2024-12-31 23:59:59')
    OR
    (u.LastAccessDate BETWEEN TIMESTAMP '2021-01-01 00:00:00' AND TIMESTAMP '2024-12-31 23:59:59')
  )
GROUP BY
  u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location
HAVING
  COUNT(DISTINCT p.Id) >= 5
ORDER BY
  AVG(p.Score) DESC,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) - SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) DESC
LIMIT 100;