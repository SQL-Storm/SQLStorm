-- {"query": "219.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 8435} 
WITH
PostTags AS (
  SELECT p.Id AS PostId,
         p.Title,
         p.Score,
         p.ViewCount,
         p.CreationDate,
         p.OwnerUserId,
         tn.TagName
  FROM Posts p
  CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS tn(TagName)
  WHERE p.PostTypeId = 1
),
TopPerTag AS (
  SELECT TagName, PostId, Title, Score, ViewCount, CreationDate, OwnerUserId,
         ROW_NUMBER() OVER (PARTITION BY TagName ORDER BY Score DESC NULLS LAST, ViewCount DESC NULLS LAST) AS rn
  FROM PostTags
),
TopPostsAllTags AS (
  SELECT TagName, PostId, Title, Score, ViewCount, CreationDate, OwnerUserId
  FROM TopPerTag
  WHERE rn = 1
),
UserActivity AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         u.Reputation,
         COALESCE(SUM(p.Score),0) AS TotalPostScore,
         COALESCE(COUNT(p.Id),0) AS PostCount,
         COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END),0) AS QuestionCount,
         COALESCE(AVG(p.ViewCount),0) AS AvgView
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id
),
BadgeCounts AS (
  SELECT UserId,
         SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
         SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
         SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
  FROM Badges
  GROUP BY UserId
),
LastActivity AS (
  SELECT p.OwnerUserId AS UserId,
         MAX(p.LastActivityDate) AS LastActive
  FROM Posts p
  GROUP BY p.OwnerUserId
),
LastPostDate AS (
  SELECT OwnerUserId AS UserId, MAX(CreationDate) AS LastPostDate
  FROM Posts
  GROUP BY OwnerUserId
),
Summary AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COALESCE(ua.TotalPostScore,0) AS TotalPostScore,
    COALESCE(ua.PostCount,0) AS PostCount,
    COALESCE(ua.QuestionCount,0) AS QuestionCount,
    COALESCE(ua.AvgView,0) AS AvgView,
    COALESCE(bc.GoldBadges,0) AS GoldBadges,
    COALESCE(bc.SilverBadges,0) AS SilverBadges,
    COALESCE(bc.BronzeBadges,0) AS BronzeBadges,
    COALESCE(la.LastActive, lp.LastPostDate) AS LastActiveDate
  FROM Users u
  LEFT JOIN UserActivity ua ON ua.UserId = u.Id
  LEFT JOIN BadgeCounts bc ON bc.UserId = u.Id
  LEFT JOIN LastActivity la ON la.UserId = u.Id
  LEFT JOIN LastPostDate lp ON lp.UserId = u.Id
),
TaggedSummary AS (
  SELECT s.UserId,
         (
           SELECT STRING_AGG(DISTINCT TagName, ',')
           FROM (
             SELECT unnest(string_to_array(substring(p.Tags,2,length(p.Tags)-2), '><')) AS TagName
             FROM Posts p
             WHERE p.OwnerUserId = s.UserId AND p.PostTypeId = 1
           ) AS TagNames
         ) AS TopTags
  FROM Summary s
),
Final AS (
  SELECT f.UserId, f.DisplayName, f.Reputation, f.TotalPostScore, f.PostCount, f.QuestionCount, f.AvgView,
         f.GoldBadges, f.SilverBadges, f.BronzeBadges, f.LastActiveDate, ts.TopTags,
         (SELECT COUNT(*) FROM TopPostsAllTags tpa WHERE tpa.OwnerUserId = f.UserId) AS TopPostsByAnyTag
  FROM Summary f
  LEFT JOIN TaggedSummary ts ON ts.UserId = f.UserId
)
SELECT *
FROM Final
ORDER BY TotalPostScore DESC NULLS LAST
LIMIT 200;