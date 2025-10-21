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
  SELECT t.TagName
  FROM Tags t
  WHERE t.Count IS NOT NULL
  ORDER BY t.Count DESC
  FETCH FIRST 1 ROWS ONLY
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
LIMIT 100;