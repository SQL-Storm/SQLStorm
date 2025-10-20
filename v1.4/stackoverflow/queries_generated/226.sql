-- {"query": "226.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 8501} 
WITH
UserBase AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    COALESCE(u.Location, 'Unknown') AS LocationNormalized
  FROM Users u
),
PostStats AS (
  SELECT
    OwnerUserId,
    SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
    COUNT(*) AS TotalPosts,
    SUM(ViewCount) AS ViewSum,
    SUM(Score) AS ScoreSum,
    MAX(LastActivityDate) AS LastActiveDate
  FROM Posts
  GROUP BY OwnerUserId
),
BadgeStats AS (
  SELECT
    UserId,
    SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
  FROM Badges
  GROUP BY UserId
),
LastActive AS (
  SELECT OwnerUserId AS UserId, MAX(LastActivityDate) AS LastActiveDate
  FROM Posts
  GROUP BY OwnerUserId
),
CommentStats AS (
  SELECT UserId, AVG(LENGTH(Text)) AS AvgCommentLen
  FROM Comments
  GROUP BY UserId
),
AvgQuestionScore AS (
  SELECT OwnerUserId AS UserId, AVG(Score) AS AvgQuestionScore
  FROM Posts
  WHERE PostTypeId = 1
  GROUP BY OwnerUserId
),
ActiveUsers AS (
  SELECT
    u.UserId,
    u.DisplayName,
    COALESCE(b.GoldBadges, 0) AS GoldBadges,
    COALESCE(b.SilverBadges, 0) AS SilverBadges,
    COALESCE(b.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(ps.TotalPosts, 0) AS TotalPosts,
    COALESCE(ps.QuestionCount, 0) AS QuestionCount,
    COALESCE(ps.ViewSum, 0) AS ViewSum,
    COALESCE(ps.ScoreSum, 0) AS ScoreSum,
    COALESCE(la.LastActiveDate, u.CreationDate) AS LastActivityDate,
    COALESCE(cc.AvgCommentLen, 0) AS AvgCommentLen,
    COALESCE(aqs.AvgQuestionScore, 0) AS AvgQuestionScore,
    u.CreationDate,
    u.LocationNormalized
  FROM UserBase u
  LEFT JOIN PostStats ps ON ps.OwnerUserId = u.UserId
  LEFT JOIN BadgeStats b ON b.UserId = u.UserId
  LEFT JOIN LastActive la ON la.UserId = u.UserId
  LEFT JOIN CommentStats cc ON cc.UserId = u.UserId
  LEFT JOIN AvgQuestionScore aqs ON aqs.UserId = u.UserId
  WHERE la.LastActiveDate IS NOT NULL AND la.LastActiveDate > now() - INTERVAL '90 days'
),
PopularUsers AS (
  SELECT
    u.UserId,
    u.DisplayName,
    COALESCE(b.GoldBadges, 0) AS GoldBadges,
    COALESCE(b.SilverBadges, 0) AS SilverBadges,
    COALESCE(b.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(ps.TotalPosts, 0) AS TotalPosts,
    COALESCE(ps.QuestionCount, 0) AS QuestionCount,
    COALESCE(ps.ViewSum, 0) AS ViewSum,
    COALESCE(ps.ScoreSum, 0) AS ScoreSum,
    COALESCE(la.LastActiveDate, u.CreationDate) AS LastActivityDate,
    COALESCE(cc.AvgCommentLen, 0) AS AvgCommentLen,
    COALESCE(aqs.AvgQuestionScore, 0) AS AvgQuestionScore,
    u.CreationDate,
    u.LocationNormalized
  FROM UserBase u
  LEFT JOIN PostStats ps ON ps.OwnerUserId = u.UserId
  LEFT JOIN BadgeStats b ON b.UserId = u.UserId
  LEFT JOIN LastActive la ON la.UserId = u.UserId
  LEFT JOIN CommentStats cc ON cc.UserId = u.UserId
  LEFT JOIN AvgQuestionScore aqs ON aqs.UserId = u.UserId
  WHERE ps.ScoreSum > 5000 OR ps.ViewSum > 50000
)
SELECT *
FROM (
  SELECT * FROM ActiveUsers
  UNION ALL
  SELECT * FROM PopularUsers
) AS unioned
ORDER BY GoldBadges DESC, ScoreSum DESC, LastActivityDate DESC
LIMIT 200;