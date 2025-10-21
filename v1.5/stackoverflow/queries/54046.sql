-- {"query": "54046.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 2107} 
SELECT
  t.TagName,
  COUNT(DISTINCT p.Id)                       AS TotalQuestions,
  AVG(p.Score)                               AS AvgScore,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes,
  SUM(CASE WHEN v.VoteTypeId IN (2,3) THEN 1 ELSE 0 END) AS TotalVotes,
  MAX(p.ViewCount)                           AS MaxViews,
  MIN(p.ViewCount)                           AS MinViews,
  AVG(p.ViewCount)                           AS AvgViews,
  MAX(u.Reputation)                          AS MaxUserRep,
  MIN(u.Reputation)                          AS MinUserRep,
  AVG(u.Reputation)                          AS AvgUserRep
FROM Posts p
JOIN Tags t
  ON p.Tags LIKE CONCAT('%', t.TagName, '%')
LEFT JOIN Votes v
  ON v.PostId = p.Id
LEFT JOIN Users u
  ON u.Id = p.OwnerUserId
WHERE p.PostTypeId = 1
GROUP BY t.TagName
ORDER BY AvgScore DESC
LIMIT 100;