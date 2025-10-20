-- {"query": "36045.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 281} 
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  COUNT(DISTINCT p.Id) AS PostCount,
  SUM(p.Score) AS ScoreSum,
  AVG(p.Score) AS AvgScore,
  MAX(p.CreationDate) AS LastPostDate,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
  COUNT(DISTINCT b.Id) AS BadgesEarned,
  MAX(b.Date) AS LastBadgeDate,
  SUM(CASE WHEN v.VoteTypeId IN (2, 3) THEN 1 ELSE 0 END) AS NetVotes
FROM
  Users AS u
  LEFT JOIN Posts AS p ON p.OwnerUserId = u.Id
  LEFT JOIN Badges AS b ON b.UserId = u.Id
  LEFT JOIN Votes AS v ON v.UserId = u.Id
WHERE
  u.Id IN (SELECT DISTINCT OwnerUserId FROM Posts WHERE OwnerUserId IS NOT NULL)
GROUP BY
  u.Id, u.DisplayName
HAVING
  COUNT(DISTINCT p.Id) > 0
ORDER BY
  NetVotes DESC,
  ScoreSum DESC
LIMIT 100;