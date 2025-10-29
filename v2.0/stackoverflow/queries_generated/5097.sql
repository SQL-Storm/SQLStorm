-- {"query": "5097.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 463} 
SELECT
  u.DisplayName AS UserName,
  u.Reputation,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesCast,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesCast,
  COUNT(DISTINCT p.Id) AS PostsCreated,
  SUM(COALESCE(p.ViewCount,0)) AS TotalViews,
  AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
  MAX(p.LastActivityDate) AS LastActive,
  COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
  COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
  STRING_AGG(DISTINCT t.Name, ',') AS TagNames,
  COUNT(DISTINCT CASE WHEN b.Id IS NOT NULL THEN b.Id END) AS BadgesEarned,
  MAX(b.Date) FILTER (WHERE b.Class = 1) AS LastGoldBadgeDate
FROM
  Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.PostId = p.Id AND v.UserId = u.Id
LEFT JOIN (
  SELECT p2.Id, unnest(string_to_array(substr(p2.Tags, 2, length(p2.Tags)-2), '><')) AS Tag
  FROM Posts p2
  WHERE p2.PostTypeId = 1
) t ON t.Id = p.Id
LEFT JOIN Badges b ON b.UserId = u.Id
LEFT JOIN (
  SELECT DISTINCT Tag FROM (
    SELECT unnest(string_to_array(substr(t.Tags, 2, length(t.Tags)-2), '><')) AS Tag
  ) AS alltags
) ts ON true
GROUP BY
  u.Id, u.DisplayName, u.Reputation
HAVING
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) > 0
ORDER BY
  Reputation DESC,
  UserName
OFFSET 100 ROWS FETCH FIRST 50 ROWS ONLY;