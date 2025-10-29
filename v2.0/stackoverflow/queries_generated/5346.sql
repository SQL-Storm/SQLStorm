-- {"query": "5346.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 345} 
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  COUNT(DISTINCT p.Id) AS PostCount,
  SUM(COALESCE(p.Score,0)) AS TotalScore,
  AVG(COALESCE(u.Reputation,0)) AS AvgReputation,
  COUNT(DISTINCT CASE WHEN pv.VoteTypeId = 2 THEN p.Id END) AS UpvotedPosts,
  COUNT(DISTINCT CASE WHEN pv.VoteTypeId = 3 THEN p.Id END) AS DownvotedPosts,
  MAX(p.LastActivityDate) AS MostRecentActivity,
  STRING_AGG(DISTINCT t.Name, ',') FILTER (WHERE t.Name IS NOT NULL) AS TagNames,
  (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id) AS BadgeCount,
  (SELECT COUNT(*) FROM Posts q WHERE q.OwnerUserId = u.Id AND q.PostTypeId = 1 AND q.AnswerCount > 0) AS QuestionsWithAnswers,
  (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) AS CommentCount
FROM
  Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Votes pv ON pv.PostId = p.Id
LEFT JOIN UNNEST(string_to_array(p.Tags, '><')) AS tname
  ON TRUE
LEFT JOIN Tags t ON LOWER(t.TagName) = LOWER(tname)
GROUP BY
  u.Id, u.DisplayName
HAVING
  COUNT(DISTINCT p.Id) > 5
ORDER BY
  TotalScore DESC, PostCount DESC
LIMIT 100;