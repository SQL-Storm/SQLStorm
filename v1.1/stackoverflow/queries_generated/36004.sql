-- {"query": "36004.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 277} 
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  COUNT(p.Id) AS PostsCreated,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
  AVG(p.Score) AS AvgPostScore,
  SUM(v.BountyAmount) AS TotalBountiesAwarded,
  MAX(p.CreationDate) AS MostRecentPostDate,
  STRING_AGG(DISTINCT t.Name, ',') AS TagsParticipated
FROM
  Users u
LEFT JOIN LATERAL (
  SELECT Id, PostTypeId, Score, CreationDate
  FROM Posts
  WHERE OwnerUserId = u.Id
) p ON TRUE
LEFT JOIN Votes v ON v.PostId = p.Id
LEFT JOIN PostLinks pl ON pl.PostId = p.Id
LEFT JOIN Tags t ON t.WikiPostId = p.Id OR t.ExcerptPostId = p.Id
GROUP BY
  u.Id, u.DisplayName, u.Reputation
HAVING
  COUNT(p.Id) > 0
ORDER BY
  TotalBountiesAwarded DESC,
  MostRecentPostDate DESC
LIMIT 100;