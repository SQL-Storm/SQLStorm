-- {"query": "5984.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 493}
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  u.Reputation,
  u.CreationDate,
  u.Views,
  u.UpVotes,
  u.DownVotes,
  COALESCE(u.Location, 'Unknown') AS Location,
  COUNT(DISTINCT p.Id) AS QuestionCount,
  AVG(p.Score) AS AvgQuestionScore,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesOnPosts,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesOnPosts,
  COUNT(DISTINCT bl.PostId) AS TotalBookmarks,
  MAX(CASE WHEN bv.PostId IS NOT NULL THEN bv.BountyAmount END) AS MaxBountyOpened,
  FIRST_VALUE(p.LastActivityDate) OVER (PARTITION BY u.Id ORDER BY p.LastActivityDate DESC) AS LastActivityDateForUser,
  (
    SELECT COUNT(*) 
    FROM Posts a
    WHERE a.OwnerUserId = u.Id AND a.PostTypeId = 2 AND a.ParentId IS NULL
      AND a.Score > 0
  ) AS PositiveAnswerCount
FROM Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
LEFT JOIN Votes v ON v.PostId = p.Id AND v.UserId = u.Id
LEFT JOIN (
  SELECT PostId, MAX(CreationDate) AS LatestVoteDate
  FROM Votes
  GROUP BY PostId
) vv ON vv.PostId = p.Id
LEFT JOIN PostLinks bl ON bl.PostId = p.Id
LEFT JOIN Votes bv ON bv.PostId = p.Id AND bv.VoteTypeId = 8
WHERE u.AccountId IS NOT NULL
  AND u.LastAccessDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '365 days'
GROUP BY
  u.Id,
  u.DisplayName,
  u.Reputation,
  u.CreationDate,
  u.Views,
  u.UpVotes,
  u.DownVotes,
  u.Location,
  p.LastActivityDate
HAVING COUNT(DISTINCT p.Id) > 0
ORDER BY u.Reputation DESC, LastActivityDateForUser DESC
LIMIT 100;