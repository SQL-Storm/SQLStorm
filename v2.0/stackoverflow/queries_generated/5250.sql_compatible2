SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  u.Reputation,
  COUNT(DISTINCT p.Id) AS QuestionCount,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived,
  MAX(u.CreationDate) AS LastActiveDate,
  STRING_AGG(DISTINCT b.Name, ',') FILTER (WHERE b.TagBased = TRUE) AS TaggedBadges,
  AVG(COALESCE(p.Score, 0)) AS AvgPostScore,
  SUM(CASE WHEN p.PostTypeId = 1 THEN COALESCE(p.ViewCount,0) ELSE 0 END) AS TotalQuestionViews,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId IN (2,3)
  LEFT JOIN Badges b ON b.UserId = u.Id
WHERE
  u.AccountId IS NOT NULL
  AND u.Reputation > 100
  AND u.LastAccessDate > (CAST('2024-10-01' AS DATE) - INTERVAL '1 year')
GROUP BY
  u.Id, u.DisplayName, u.Reputation, u.CreationDate
HAVING
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) > 5
ORDER BY
  SUM(CASE WHEN p.PostTypeId = 1 THEN COALESCE(p.ViewCount,0) ELSE 0 END) DESC,
  (SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) - SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)) DESC
LIMIT 100;