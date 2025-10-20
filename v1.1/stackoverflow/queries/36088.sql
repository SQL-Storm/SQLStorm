-- {"query": "36088.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 236} 
SELECT
  u.Id AS UserId,
  u.DisplayName,
  COUNT(DISTINCT p.Id) AS TotalPosts,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
  AVG(p.Score) AS AvgPostScore,
  MAX(p.LastActivityDate) AS LastActive,
  r.Reputation AS UserReputation,
  COUNT(DISTINCT b.Id) AS BadgesEarned
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN (
    SELECT Id, Reputation
    FROM Users
  ) r ON r.Id = u.Id
WHERE
  u.Id IS NOT NULL
GROUP BY
  u.Id, u.DisplayName, r.Reputation
HAVING
  COUNT(DISTINCT p.Id) > 0
ORDER BY
  TotalPosts DESC, UserReputation DESC
LIMIT 100;