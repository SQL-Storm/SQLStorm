SELECT
  u.DisplayName AS TopUser,
  u.Id AS UserId,
  COUNT(p.Id) AS PostCount,
  AVG(p.Score) AS AvgPostScore,
  SUM(p.ViewCount) AS TotalViews,
  MAX(p.LastActivityDate) AS LastActive,
  STRING_AGG(DISTINCT tt.Name, ',') AS PostTypesUsed,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
  SUM(CASE WHEN c.Id IS NOT NULL THEN 1 ELSE 0 END) AS CommentCount
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId IN (2,3)
  LEFT JOIN Comments c ON c.PostId = p.Id
  LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
  LEFT JOIN (
    SELECT DISTINCT p2.OwnerUserId, pt2.Name
    FROM Posts p2
    JOIN PostTypes pt2 ON p2.PostTypeId = pt2.Id
    JOIN (SELECT Id, Name FROM PostHistoryTypes WHERE Id IN (1,2,4,5,6)) AS ph ON 1=1
    GROUP BY p2.OwnerUserId, pt2.Name
  ) AS tt ON tt.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT DISTINCT Id, Name FROM PostHistoryTypes
  ) AS pht ON 1=1
WHERE
  u.AccountId IS NOT NULL
GROUP BY
  u.Id,
  u.DisplayName,
  tt.Name
ORDER BY
  TotalViews DESC, PostCount DESC
LIMIT 100;