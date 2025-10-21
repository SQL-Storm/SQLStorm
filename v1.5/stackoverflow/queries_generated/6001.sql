-- {"query": "6001.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 326} 
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  u.Reputation,
  u.CreationDate,
  COUNT(DISTINCT p.Id) AS PostCount,
  AVG(COALESCE(v.BountyAmount, 0)) AS AvgBounty,
  MAX(p.LastActivityDate) AS LastActivity,
  STRING_AGG(DISTINCT tt.Name, ',') AS TopPostTypes,
  SUM(CASE WHEN pv.Voted ELSE 0 END) AS DummyFlag -- placeholder to force a correlated expression
FROM
  Users u
LEFT JOIN
  Posts p ON p.OwnerUserId = u.Id
LEFT JOIN
  LATERAL (
    SELECT
      SUM(CASE WHEN v.VoteTypeId IN (2, 3, 12) THEN 1 ELSE 0 END) AS Voted
    FROM
      Votes v
    WHERE
      v.PostId = p.Id
  ) pv ON TRUE
LEFT JOIN
  Votes v ON v.PostId = p.Id
LEFT JOIN
  PostTypes pt ON pt.Id = p.PostTypeId
LEFT JOIN
  (
    SELECT DISTINCT
      pt.Id,
      pt.Name
    FROM
      Posts p2
    JOIN
      PostTypes pt ON pt.Id = p2.PostTypeId
  ) tt ON tt.Id = p.PostTypeId
GROUP BY
  u.Id, u.DisplayName, u.Reputation, u.CreationDate
ORDER BY
  Reputation DESC, LastActivity DESC
LIMIT 100;