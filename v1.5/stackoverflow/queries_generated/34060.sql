-- {"query": "34060.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 1028} 

WITH UserQuestionStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
    COALESCE(SUM(p.Score), 0) AS TotalPostScore,
    MAX(p.CreationDate) FILTER (WHERE p.PostTypeId = 1) AS LastQuestionDate
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName
),
HighReputationUsers AS (
  SELECT UserId, DisplayName, QuestionCount, AnswerCount, TotalPostScore, LastQuestionDate
  FROM UserQuestionStats
  WHERE QuestionCount > 5 AND TotalPostScore > 1000
),
TagPopularity AS (
  SELECT
    unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) AS Tag,
    COUNT(*) AS TagCount,
    AVG(p.Score) AS AvgScore
  FROM Posts p
  WHERE p.PostTypeId = 1 -- questions only
  GROUP BY Tag
  HAVING COUNT(*) > 50
),
TopTags AS (
  SELECT Tag
  FROM TagPopularity
  ORDER BY TagCount DESC, AvgScore DESC
  LIMIT 10
),
UserBadgeSummary AS (
  SELECT
    b.UserId,
    COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
    COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
    COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
    COUNT(DISTINCT b.Name) AS DistinctBadges,
    MAX(b.Date) AS LastBadgeDate
  FROM Badges b
  GROUP BY b.UserId
),
UserActivity AS (
  SELECT
    u.Id AS UserId,
    COUNT(DISTINCT ph.PostId) AS EditedPosts,
    COUNT(DISTINCT c.Id) AS CommentCount
  FROM Users u
  LEFT JOIN PostHistory ph ON ph.UserId = u.Id AND ph.CreationDate > NOW() - INTERVAL '1 year'
  LEFT JOIN Comments c ON c.UserId = u.Id AND c.CreationDate > NOW() - INTERVAL '1 year'
  GROUP BY u.Id
),
QualifiedUsers AS (
  SELECT
    hu.UserId,
    hu.DisplayName,
    hu.QuestionCount,
    hu.AnswerCount,
    hu.TotalPostScore,
    hu.LastQuestionDate,
    COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
    COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(ubs.DistinctBadges, 0) AS DistinctBadges,
    COALESCE(ua.EditedPosts, 0) AS EditedPosts,
    COALESCE(ua.CommentCount, 0) AS CommentCount
  FROM HighReputationUsers hu
  LEFT JOIN UserBadgeSummary ubs ON ubs.UserId = hu.UserId
  LEFT JOIN UserActivity ua ON ua.UserId = hu.UserId
  WHERE COALESCE(ubs.GoldBadges, 0) > 0 AND COALESCE(ua.CommentCount, 0) > 20
)
SELECT
  qu.UserId,
  qu.DisplayName,
  qu.QuestionCount,
  qu.AnswerCount,
  qu.TotalPostScore,
  qu.GoldBadges,
  qu.SilverBadges,
  qu.BronzeBadges,
  qu.DistinctBadges,
  qu.EditedPosts,
  qu.CommentCount,
  tt.Tag,
  tp.TagCount,
  tp.AvgScore,
  (
    SELECT COUNT(*)
    FROM Posts p
    WHERE p.OwnerUserId = qu.UserId
      AND p.PostTypeId = 1
      AND p.Tags LIKE '%' || tt.Tag || '%'
      AND p.Score > (SELECT AVG(score) FROM Posts WHERE PostTypeId = 1)
  ) AS UserQuestionCountForTag,
  (
    SELECT AVG(v.Score)
    FROM Votes v
    JOIN Posts p ON v.PostId = p.Id
    WHERE p.OwnerUserId = qu.UserId
      AND p.PostTypeId = 1
      AND p.Tags LIKE '%' || tt.Tag || '%'
      AND v.VoteTypeId = 2 -- UpMod
  ) AS AvgUpvoteScoreForTag
FROM QualifiedUsers qu
CROSS JOIN TopTags tt
JOIN TagPopularity tp ON tp.Tag = tt.Tag
ORDER BY qu.TotalPostScore DESC, qu.GoldBadges DESC, tp.TagCount DESC
LIMIT 100;
