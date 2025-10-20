-- {"query": "148.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2152} 
WITH UserPostStats AS (
  SELECT
    OwnerUserId AS UserId,
    SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
    SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
    SUM(COALESCE(Score, 0)) AS TotalScore,
    MAX(LastActivityDate) AS LastActivityDate
  FROM Posts
  GROUP BY OwnerUserId
),
LastActivityPerUser AS (
  SELECT
    p.OwnerUserId AS UserId,
    p.LastActivityDate
  FROM Posts p
  INNER JOIN (
    SELECT OwnerUserId, MAX(LastActivityDate) AS MaxLA
    FROM Posts
    GROUP BY OwnerUserId
  ) m ON p.OwnerUserId = m.OwnerUserId AND p.LastActivityDate = m.MaxLA
),
RecentVotes AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId IN (2, 3) THEN 1 ELSE -1 END) AS NetVotes
  FROM Votes v
  GROUP BY v.PostId
),
TagEngagement AS (
  SELECT
    p.Id AS PostId,
    unnest(string_to_array(substr(p.Tags, 2, length(p.Tags) - 2), '><')) AS TagName
  FROM Posts p
  WHERE p.PostTypeId = 1
),
TopTags AS (
  SELECT
    te.UserId,
    te.TagName,
    COUNT(*) AS TagCount,
    ROW_NUMBER() OVER (PARTITION BY te.UserId ORDER BY COUNT(*) DESC) AS rn
  FROM TagEngagement te
  JOIN Posts p ON p.Id = te.PostId
  GROUP BY te.UserId, te.TagName
)
SELECT
  u.Id,
  u.DisplayName,
  u.Reputation,
  COALESCE(ups.QuestionCount, 0) AS QuestionCount,
  COALESCE(ups.AnswerCount, 0) AS AnswerCount,
  COALESCE(ups.TotalScore, 0) AS TotalScore,
  COALESCE(lapu.LastActivityDate, NULL) AS LastActivityDate,
  COALESCE(badge_count.TotalBadges, 0) AS BadgeCount,
  COALESCE(tt.TopTag, NULL) AS TopTag
FROM Users u
LEFT JOIN UserPostStats ups ON ups.UserId = u.Id
LEFT JOIN LastActivityPerUser lapu ON lapu.UserId = u.Id
LEFT JOIN (
  SELECT UserId, COUNT(*) AS TotalBadges
  FROM Badges
  GROUP BY UserId
) badge_count ON badge_count.UserId = u.Id
LEFT JOIN (
  SELECT UserId, TagName AS TopTag
  FROM TopTags
  WHERE rn = 1
) tt ON tt.UserId = u.Id
ORDER BY u.Reputation DESC
LIMIT 100;