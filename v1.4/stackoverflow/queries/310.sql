-- {"query": "310.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 19790} 
WITH
ActiveUsers AS (
  SELECT Id, DisplayName, Reputation, LastAccessDate, Location, WebsiteUrl, AboutMe, AccountId
  FROM Users
  WHERE LastAccessDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '180 days'
),
InactiveUsers AS (
  SELECT Id, DisplayName, Reputation, LastAccessDate, Location, WebsiteUrl, AboutMe, AccountId
  FROM Users
  WHERE LastAccessDate <= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '180 days'
),
UserPostStats AS (
  SELECT OwnerUserId AS UserId,
         SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
         SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
         AVG(CASE WHEN PostTypeId = 1 THEN Score END) AS AvgQuestionScore
  FROM Posts
  GROUP BY OwnerUserId
),
UserVotes AS (
  SELECT p.OwnerUserId AS UserId,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesOnPosts,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesOnPosts
  FROM Votes v
  JOIN Posts p ON p.Id = v.PostId
  GROUP BY p.OwnerUserId
),
UserBadges AS (
  SELECT b.UserId,
         COUNT(*) AS BadgesCount,
         MAX(b.Date) AS LastBadgeDate
  FROM Badges b
  GROUP BY b.UserId
),
TagCounts AS (
  SELECT p.OwnerUserId AS UserId,
         t.TagName,
         COUNT(*) AS TagCount
  FROM Posts p
  CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS t(TagName)
  WHERE p.PostTypeId = 1
  GROUP BY p.OwnerUserId, t.TagName
),
TopTags AS (
  SELECT UserId,
         STRING_AGG(TagName, ', ') AS TopTags
  FROM (
     SELECT UserId, TagName, TagCount,
            ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY TagCount DESC, TagName) AS rn
     FROM TagCounts
  ) s
  WHERE rn <= 3
  GROUP BY UserId
),
ActiveSet AS (
  SELECT
     u.Id AS UserId,
     u.DisplayName,
     u.Reputation,
     u.LastAccessDate,
     u.Location,
     u.WebsiteUrl,
     u.AboutMe,
     u.AccountId,
     COALESCE(ps.QuestionCount, 0) AS QuestionCount,
     COALESCE(ps.AnswerCount, 0) AS AnswerCount,
     COALESCE(ps.AvgQuestionScore, 0) AS AvgQuestionScore,
     COALESCE(vs.UpVotesOnPosts, 0) AS UpVotesOnPosts,
     COALESCE(vs.DownVotesOnPosts, 0) AS DownVotesOnPosts,
     COALESCE(nb.BadgesCount, 0) AS BadgesCount,
     nb.LastBadgeDate,
     COALESCE(ts.TopTags, '') AS TopTags,
     (SELECT MAX(p.LastEditDate) FROM Posts p WHERE p.OwnerUserId = u.Id) AS LastPostEditDate,
     (SELECT p.LastEditorDisplayName FROM Posts p WHERE p.OwnerUserId = u.Id ORDER BY p.LastEditDate DESC LIMIT 1) AS LastPostEditorName,
     LENGTH(COALESCE(u.Location, '')) AS LocationLength,
     CASE
       WHEN (COALESCE(ps.QuestionCount, 0) + COALESCE(ps.AnswerCount, 0)) > 0
       THEN ((COALESCE(ps.QuestionCount, 0) * 1.0) / (COALESCE(ps.QuestionCount, 0) + COALESCE(ps.AnswerCount, 0))) * 0.6
            + CASE WHEN u.LastAccessDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '180 days' THEN 0.4 ELSE 0 END
       ELSE 0
     END AS QualityScore,
     'Active' AS Status
  FROM ActiveUsers u
  LEFT JOIN UserPostStats ps ON ps.UserId = u.Id
  LEFT JOIN UserVotes vs ON vs.UserId = u.Id
  LEFT JOIN UserBadges nb ON nb.UserId = u.Id
  LEFT JOIN TopTags ts ON ts.UserId = u.Id
),
InactiveSet AS (
  SELECT
     u.Id AS UserId,
     u.DisplayName,
     u.Reputation,
     u.LastAccessDate,
     u.Location,
     u.WebsiteUrl,
     u.AboutMe,
     u.AccountId,
     COALESCE(ps.QuestionCount, 0) AS QuestionCount,
     COALESCE(ps.AnswerCount, 0) AS AnswerCount,
     COALESCE(ps.AvgQuestionScore, 0) AS AvgQuestionScore,
     COALESCE(vs.UpVotesOnPosts, 0) AS UpVotesOnPosts,
     COALESCE(vs.DownVotesOnPosts, 0) AS DownVotesOnPosts,
     COALESCE(nb.BadgesCount, 0) AS BadgesCount,
     nb.LastBadgeDate,
     COALESCE(ts.TopTags, '') AS TopTags,
     (SELECT MAX(p.LastEditDate) FROM Posts p WHERE p.OwnerUserId = u.Id) AS LastPostEditDate,
     (SELECT p.LastEditorDisplayName FROM Posts p WHERE p.OwnerUserId = u.Id ORDER BY p.LastEditDate DESC LIMIT 1) AS LastPostEditorName,
     LENGTH(COALESCE(u.Location, '')) AS LocationLength,
     CASE
       WHEN (COALESCE(ps.QuestionCount, 0) + COALESCE(ps.AnswerCount, 0)) > 0
       THEN ((COALESCE(ps.QuestionCount, 0) * 1.0) / (COALESCE(ps.QuestionCount, 0) + COALESCE(ps.AnswerCount, 0))) * 0.6
            + CASE WHEN u.LastAccessDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '180 days' THEN 0.4 ELSE 0 END
       ELSE 0
     END AS QualityScore,
     'Inactive' AS Status
  FROM InactiveUsers u
  LEFT JOIN UserPostStats ps ON ps.UserId = u.Id
  LEFT JOIN UserVotes vs ON vs.UserId = u.Id
  LEFT JOIN UserBadges nb ON nb.UserId = u.Id
  LEFT JOIN TopTags ts ON ts.UserId = u.Id
)
SELECT * FROM ActiveSet
UNION ALL
SELECT * FROM InactiveSet
ORDER BY Reputation DESC, UserId;