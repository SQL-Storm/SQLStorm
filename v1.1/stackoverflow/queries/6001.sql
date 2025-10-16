SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  u.Reputation,
  u.CreationDate,
  COUNT(DISTINCT p.Id) AS PostCount,
  AVG(COALESCE(v.BountyAmount, 0)) AS AvgBounty,
  MAX(p.LastActivityDate) AS LastActivity,
  STRING_AGG(DISTINCT tt.Name, ',') AS TopPostTypes,
  SUM(COALESCE(pv.Voted, 0)) AS DummyFlag
FROM
  Users u
LEFT JOIN
  Posts p ON p.OwnerUserId = u.Id
LEFT JOIN LATERAL (
  SELECT
    SUM(CASE WHEN v2.VoteTypeId IN (2, 3, 12) THEN 1 ELSE 0 END) AS Voted
  FROM
    Votes v2
  WHERE
    v2.PostId = p.Id
) pv ON TRUE
LEFT JOIN
  Votes v ON v.PostId = p.Id
LEFT JOIN
  PostTypes pt ON pt.Id = p.PostTypeId
LEFT JOIN (
  SELECT DISTINCT
    pt2.Id,
    pt2.Name
  FROM
    Posts p2
  JOIN
    PostTypes pt2 ON pt2.Id = p2.PostTypeId
) tt ON tt.Id = p.PostTypeId
GROUP BY
  u.Id, u.DisplayName, u.Reputation, u.CreationDate
ORDER BY
  Reputation DESC, LastActivity DESC
LIMIT 100;