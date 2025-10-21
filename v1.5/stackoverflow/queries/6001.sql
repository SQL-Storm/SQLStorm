SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  u.Reputation,
  u.CreationDate,
  COUNT(DISTINCT p.Id) AS PostCount,
  AVG(COALESCE(v.BountyAmount, 0)) AS AvgBounty,
  MAX(p.LastActivityDate) AS LastActivity,
  STRING_AGG(DISTINCT tt.Name, ',') AS TopPostTypes,
  SUM(CASE WHEN pv.Voted IS NOT NULL THEN pv.Voted ELSE 0 END) AS DummyFlag
FROM
  Users u
LEFT JOIN
  Posts p ON p.OwnerUserId = u.Id
LEFT JOIN
  (
    SELECT
      v.PostId,
      SUM(CASE WHEN v.VoteTypeId IN (2, 3, 12) THEN 1 ELSE 0 END) AS Voted
    FROM
      Votes v
    GROUP BY
      v.PostId
  ) pv ON pv.PostId = p.Id
LEFT JOIN
  Votes v ON v.PostId = p.Id
LEFT JOIN
  PostTypes pt ON pt.Id = p.PostTypeId
LEFT JOIN
  (
    SELECT DISTINCT
      pt.Id AS Id,
      pt.Name AS Name
    FROM
      Posts p2
    JOIN
      PostTypes pt ON pt.Id = p2.PostTypeId
  ) tt ON tt.Id = p.PostTypeId
GROUP BY
  u.Id, u.DisplayName, u.Reputation, u.CreationDate
ORDER BY
  u.Reputation DESC, MAX(p.LastActivityDate) DESC
LIMIT 100;