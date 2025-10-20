-- {"query": "138.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 1288} 
WITH UserStats AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         u.Reputation,
         u.CreationDate,
         COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
         COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount,
         MAX(p.Score) AS MaxPostScore
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
RecentVotes AS (
  SELECT v.UserId,
         MAX(v.CreationDate) AS LastVoteDate,
         SUM(v.BountyAmount) AS TotalBounty
  FROM Votes v
  GROUP BY v.UserId
),
MostUsedTag AS (
  SELECT TOP (1) t.TagName
  FROM Tags t
  WHERE t.Count IS NOT NULL
  ORDER BY t.Count DESC
)
SELECT
  us.UserId,
  us.DisplayName,
  us.Reputation,
  us.CreationDate,
  us.QuestionCount,
  us.AnswerCount,
  us.MaxPostScore,
  rv.LastVoteDate,
  rv.TotalBounty,
  MUT.TagName AS MostUsedTag
FROM UserStats us
LEFT JOIN RecentVotes rv ON rv.UserId = us.UserId
CROSS JOIN MostUsedTag MUT
ORDER BY us.Reputation DESC, us.CreationDate ASC
OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY;