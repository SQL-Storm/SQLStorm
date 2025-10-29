-- {"query": "5073.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 390} 
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  u.Reputation,
  COUNT(DISTINCT p.Id) AS PostsCreated,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
  MAX(p.LastActivityDate) AS LastActivity,
  AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
  ARRAY_AGG(DISTINCT t.Name) FILTER (WHERE p.PostTypeId = 1) AS QuestionTags,
  SUM(CASE WHEN b.Id IS NOT NULL THEN 1 ELSE 0 END) AS BadgesEarned,
  COUNT(DISTINCT bh.Id) AS HistoryEntries,
  SUM(CASE WHEN bh.PostHistoryTypeId = 52 THEN 1 ELSE 0 END) AS HotNetworkQuestionVotes,
  (CASE
     WHEN u.AccountId IS NOT NULL THEN u.AccountId
     ELSE -1
   END) AS AccountIdentifier
FROM
  Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.PostId = p.Id
LEFT JOIN PostHistory bh ON bh.PostId = p.Id
LEFT JOIN Badges b ON b.UserId = u.Id
LEFT JOIN LATERAL (
  SELECT Id, Name
  FROM Tags t
  WHERE p.PostTypeId = 1 AND p.Tags LIKE '%' || t.TagName || '%'
) t ON TRUE
GROUP BY
  u.Id, u.DisplayName, u.Reputation, u.AccountId
HAVING
  COUNT(DISTINCT p.Id) > 0
ORDER BY
  Reputation DESC, PostsCreated DESC
LIMIT 100;