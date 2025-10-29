-- {"query": "5590.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 488} 
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  u.Reputation,
  u.CreationDate,
  u.LastAccessDate,
  COALESCE(u.Location, 'Unknown') AS Location,
  COALESCE(u.AboutMe, '') AS About,
  COALESCE(COUNT(DISTINCT p.Id) FILTER (WHERE pt.Name = 'Question'), 0) AS QuestionCount,
  COALESCE(COUNT(v.Id) FILTER (WHERE vt.Name IN ('UpMod','AcceptedByOriginator','ModeratorReview')), 0) AS EngagementVotes,
  COALESCE(SUM(CASE WHEN v.VoteTypeId = vt_up.Id THEN 1 ELSE 0 END) OVER (PARTITION BY u.Id), 0) AS UpvotesGiven,
  COALESCE(SUM(CASE WHEN v.VoteTypeId = vt_down.Id THEN 1 ELSE 0 END) OVER (PARTITION BY u.Id), 0) AS DownvotesGiven,
  MAX(p.LastActivityDate) AS LastActivity,
  ARRAY_AGG(DISTINCT t.TagName) FILTER (WHERE t.TagName IS NOT NULL) AS TopTags
FROM Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN Votes v ON v.PostId = p.Id
LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
LEFT JOIN (SELECT Id, Name FROM VoteTypes WHERE Name IN ('UpMod','AcceptedByOriginator','ModeratorReview')) vt_up ON vt_up.Name = 'UpMod'
LEFT JOIN (SELECT Id, Name FROM VoteTypes WHERE Name = 'DownMod') vt_down ON vt_down.Name = 'DownMod'
LEFT JOIN (SELECT Id, TagName, Count FROM Tags) t ON t.Id = p.Tags::INT  -- assume Tags stores tag IDs in a compatible DB
GROUP BY
  u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location, u.AboutMe
HAVING
  COALESCE(COUNT(DISTINCT p.Id) FILTER (WHERE pt.Name = 'Question'), 0) > 0
ORDER BY
  u.Reputation DESC,
  LastActivity DESC
LIMIT 100;