-- {"query": "5982.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 514} 
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  COUNT(p.Id) AS PostCount,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
  AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS AvgPostScore,
  MAX(p.LastActivityDate) AS LastActiveDate,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
  COUNT(DISTINCT bl.Id) AS BadgesEarned,
  STRING_AGG(DISTINCT CASE WHEN b.Name IS NOT NULL THEN b.Name ELSE NULL END, ',') AS BadgeNames,
  -- Correlated subquery: number of comments this user made on their own posts
  (SELECT COUNT(*) FROM Comments c
   WHERE c.UserId = u.Id OR c.UserDisplayName = u.DisplayName) AS CommentsByUserAcrossPosts,
  -- Window function: rank users by reputation within current week of CreationDate
  RANK() OVER (
    ORDER BY u.Reputation DESC
  ) AS ReputationRank,
  -- Complex expression: compute a derived score for the user
  (COALESCE(u.Reputation,0) * 2 +
   COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0) +
   COALESCE(SUM(p.ViewCount),0) * 0.001) AS DerivedScore
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN Badges bl ON bl.UserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
WHERE
  -- Consider users created in the last 5 years and with at least 1 post
  u.CreationDate >= CURRENT_DATE - INTERVAL '5 years'
  AND (p.Id IS NULL OR p.Id IS NOT NULL)
GROUP BY
  u.Id,
  u.DisplayName,
  u.Reputation,
  u.UpVotes,
  u.DownVotes
ORDER BY
  DerivedScore DESC
LIMIT 100;