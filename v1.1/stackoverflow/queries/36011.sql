SELECT
  u.Id AS UserId,
  u.DisplayName,
  COUNT(p.Id) AS PostCount,
  AVG(p.Score) AS AvgPostScore,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived,
  MAX(p.CreationDate) AS LastPostDate,
  MAX(v.CreationDate) AS LastVoteDate,
  COUNT(DISTINCT bl.Id) AS BadgesEarned,
  AVG(
    EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - CAST(u.CreationDate AS TIMESTAMP))) / 86400.0
  ) AS AverageAccountAgeDays
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN Badges bl ON bl.UserId = u.Id
WHERE
  CAST(u.CreationDate AS TIMESTAMP) < TIMESTAMP '2024-10-01 12:34:56'
GROUP BY
  u.Id,
  u.DisplayName,
  u.CreationDate
HAVING
  COUNT(p.Id) > 0
ORDER BY
  AvgPostScore DESC,
  PostCount DESC
LIMIT 100;