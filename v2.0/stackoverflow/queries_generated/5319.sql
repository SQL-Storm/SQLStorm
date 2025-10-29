-- {"query": "5319.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 450} 
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  COUNT(DISTINCT p.Id) AS PostsCreated,
  AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) AS AvgQuestionScore,
  AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) AS AvgAnswerScore,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived,
  MAX(p.LastActivityDate) AS LastActivity,
  STRING_AGG(DISTINCT t.Name, ',') FILTER (WHERE t.Name IS NOT NULL) AS TagNames,
  COUNT(DISTINCT bl.Id) AS BadgesEarned,
  MAX(CASE WHEN b.Class = 1 THEN b.Date END) AS GoldBadgeDate,
  MAX(CASE WHEN b.Class = 2 THEN b.Date END) AS SilverBadgeDate,
  MAX(CASE WHEN b.Class = 3 THEN b.Date END) AS BronzeBadgeDate
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN (
    SELECT
      p.OwnerUserId AS UserId,
      t.Name
    FROM Posts p
      LEFT JOIN PostTags tg ON tg.PostId = p.Id
      LEFT JOIN Tags t ON t.Id = tg.TagId
    WHERE p.OwnerUserId IS NOT NULL
  ) t ON t.UserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN Badges bl ON bl.UserId = u.Id -- alias to reference any badge dates in aggregates
WHERE
  u.AccountId IS NOT NULL
GROUP BY
  u.Id,
  u.DisplayName,
  u.Reputation
HAVING
  COUNT(DISTINCT p.Id) > 0
ORDER BY
  u.Reputation DESC,
  PostsCreated DESC
LIMIT 100;