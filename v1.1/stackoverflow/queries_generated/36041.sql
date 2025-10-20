-- {"query": "36041.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 280} 
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  u.CreationDate,
  u.LastAccessDate,
  COUNT(p.Id) AS PostCount,
  AVG(p.Score) AS AvgPostScore,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
  COALESCE(SUM(v.BountyAmount), 0) AS TotalBountiesAwarded,
  COUNT(DISTINCT bh.PostId) AS EditedPosts,
  MAX(p.LastActivityDate) AS LastActiveDate
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId = 8 -- BountyStart
  LEFT JOIN PostHistory bh ON bh.PostId = p.Id
WHERE
  u.Id IN (SELECT DISTINCT OwnerUserId FROM Posts WHERE OwnerUserId IS NOT NULL)
GROUP BY
  u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
ORDER BY
  TotalBountiesAwarded DESC, PostCount DESC
LIMIT 100;