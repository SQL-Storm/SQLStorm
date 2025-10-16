-- {"query": "6018.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 384} 
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  COUNT(DISTINCT p.Id) AS PostCount,
  AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
  AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgAnswerScore,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
  STRING_AGG(DISTINCT bt.Name, ',') FILTER (WHERE bt.Name IS NOT NULL) AS BadgesEarned,
  MAX(p.LastActivityDate) AS LastActivity,
  SUM(CASE WHEN c.Id IS NOT NULL THEN 1 ELSE 0 END) AS CommentCount,
  SUM(CASE WHEN b.Id IS NOT NULL THEN 1 ELSE 0 END) AS BadgesCount
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN Badges bb ON bb.UserId = u.Id AND bb.Id = b.Id -- self-reference to enable DISTINCT badge names per user
  LEFT JOIN PostHistory ph ON ph.UserId = u.Id
  LEFT JOIN (SELECT DISTINCT UserId, Name FROM Badges) AS bt ON bt.UserId = u.Id
  LEFT JOIN Comments c ON c.UserId = u.Id
WHERE
  u.AccountId IS NOT NULL
GROUP BY
  u.Id, u.DisplayName, u.Reputation
ORDER BY
  Reputation DESC, PostCount DESC
LIMIT 100;