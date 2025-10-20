-- {"query": "36062.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 274} 
SELECT
  u.Id AS UserId,
  u.DisplayName,
  COUNT(DISTINCT p.Id) AS TotalPosts,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsCreated,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersPosted,
  MAX(p.CreationDate) AS LastActivity,
  SUM(COALESCE(v.BountyAmount,0)) AS TotalBountiesAwarded,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived,
  SUM(COALESCE(p.ViewCount,0)) AS ViewCountSum,
  COUNT(DISTINCT b.Id) AS BadgesEarned
FROM
  Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.PostId = p.Id AND v.UserId = u.Id
LEFT JOIN Badges b ON b.UserId = u.Id
GROUP BY
  u.Id, u.DisplayName
ORDER BY
  TotalPosts DESC, LastActivity DESC
LIMIT 100;