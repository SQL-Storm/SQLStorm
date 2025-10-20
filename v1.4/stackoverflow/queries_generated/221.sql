-- {"query": "221.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 10007} 
WITH
base AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.LastAccessDate,
    u.Location,
    u.WebsiteUrl,
    u.AccountId
  FROM Users u
),
user_stats AS (
  SELECT
    b.UserId,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
    AVG(p.Score) AS AvgScore,
    MAX(p.LastActivityDate) AS LastActivity
  FROM base b
  LEFT JOIN Posts p ON p.OwnerUserId = b.UserId
  GROUP BY b.UserId
),
user_badges AS (
  SELECT b.UserId, COUNT(*) AS BadgeCount, MAX(b.Date) AS LastBadgeDate
  FROM Badges b
  GROUP BY b.UserId
),
user_comments AS (
  SELECT p.OwnerUserId AS UserId, COUNT(c.Id) AS CommentCount
  FROM Posts p
  LEFT JOIN Comments c ON c.PostId = p.Id
  GROUP BY p.OwnerUserId
),
tags_by_user AS (
  SELECT p.OwnerUserId AS UserId,
         STRING_AGG(DISTINCT tname, ',') AS TagList
  FROM Posts p
  LEFT JOIN LATERAL (
     SELECT unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS tname
  ) t ON TRUE
  GROUP BY p.OwnerUserId
),
latest_votes AS (
  SELECT v.UserId, MAX(v.CreationDate) AS LastVoteDate
  FROM Votes v
  GROUP BY v.UserId
)
SELECT
  u.UserId,
  u.DisplayName,
  u.Reputation,
  COALESCE(ub.BadgeCount, 0) AS BadgeCount,
  COALESCE(us.QuestionCount, 0) AS QuestionCount,
  COALESCE(us.AnswerCount, 0) AS AnswerCount,
  COALESCE(us.AvgScore, 0) AS AvgPostScore,
  COALESCE(us.LastActivity, u.LastAccessDate) AS LastActivityDate,
  COALESCE(uc.CommentCount, 0) AS CommentCountOnPosts,
  COALESCE(ub.LastBadgeDate, NULL) AS LastBadgeDate,
  COALESCE(tb.TagList, '') AS TagList,
  CONCAT('user-', u.UserId) AS Slug,
  NOW() AS BenchmarkTime
FROM base u
LEFT JOIN user_stats us ON u.UserId = us.UserId
LEFT JOIN user_badges ub ON u.UserId = ub.UserId
LEFT JOIN user_comments uc ON u.UserId = uc.UserId
LEFT JOIN latest_votes lv ON u.UserId = lv.UserId
LEFT JOIN tags_by_user tb ON u.UserId = tb.UserId
ORDER BY u.Reputation DESC NULLS LAST
LIMIT 200
UNION ALL
SELECT
  u.UserId,
  u.DisplayName,
  u.Reputation,
  COALESCE(ub.BadgeCount, 0),
  COALESCE(us.QuestionCount, 0),
  COALESCE(us.AnswerCount, 0),
  COALESCE(us.AvgScore, 0),
  COALESCE(us.LastActivity, u.LastAccessDate),
  COALESCE(uc.CommentCount, 0),
  COALESCE(ub.LastBadgeDate, NULL),
  COALESCE(tb.TagList, ''),
  CONCAT('user-', u.UserId),
  NOW()
FROM base u
LEFT JOIN user_stats us ON u.UserId = us.UserId
LEFT JOIN user_badges ub ON u.UserId = ub.UserId
LEFT JOIN user_comments uc ON u.UserId = uc.UserId
LEFT JOIN latest_votes lv ON u.UserId = lv.UserId
LEFT JOIN tags_by_user tb ON u.UserId = tb.UserId
WHERE u.LastAccessDate < NOW() - INTERVAL '1 year'
ORDER BY u.LastAccessDate ASC
LIMIT 100;