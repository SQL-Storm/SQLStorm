-- {"query": "6090.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 346} 
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  COUNT(DISTINCT p.Id) AS QuestionCount,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived,
  MAX(p.CreationDate) AS LastQuestionDate,
  AVG(p.Score) AS AvgQuestionScore,
  COUNT(DISTINCT b.Id) AS BadgesEarned,
  COALESCE(MAX(b.Date), TIMESTAMP '1970-01-01') AS LastBadgeDate,
  STRING_AGG(DISTINCT t.Name, ',') AS TopTags
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
  LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId IN (2,3)
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN (
    SELECT
      TagName,
      Count,
      WikiPostId
    FROM Tags
    WHERE IsModeratorOnly = 0
  ) t ON t.WikiPostId = p.Id
WHERE
  u.AccountId IS NOT NULL
  AND u.Reputation >= 100
GROUP BY
  u.Id,
  u.DisplayName,
  u.Reputation
HAVING
  COUNT(DISTINCT p.Id) > 0
ORDER BY
  UpvotesReceived DESC,
  LastQuestionDate DESC
LIMIT 100;