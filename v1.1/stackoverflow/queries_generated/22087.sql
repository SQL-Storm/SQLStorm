-- {"query": "22087.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 973} 

WITH UserStats AS (
  SELECT u.Id, u.DisplayName, u.CreationDate,
         COUNT(p.Id) AS QuestionCount,
         AVG(p.Score) AS AvgQuestionScore,
         STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') AS PopularTags
  FROM Users u
  LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
  GROUP BY u.Id, u.DisplayName, u.CreationDate
),
CommentStats AS (
  SELECT c.UserId, COUNT(*) AS CommentCount,
         SUM(c.Score) AS TotalCommentScore,
         MAX(c.Score) AS MaxCommentScore
  FROM Comments c
  GROUP BY c.UserId
),
BadgeStats AS (
  SELECT b.UserId,
         COUNT(*) AS BadgeCount,
         COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
         COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
         COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
         SUM(CASE WHEN b.Class = 1 THEN 10 WHEN b.Class = 2 THEN 5 ELSE 1 END) AS BadgePoints
  FROM Badges b
  GROUP BY b.UserId
),
VoteStats AS (
  SELECT v.UserId,
         COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpvoteCount,
         COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownvoteCount,
         SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) AS TotalBountiesStarted
  FROM Votes v
  GROUP BY v.UserId
),
AnswerStats AS (
  SELECT p.ParentId,
         COUNT(*) AS AnswerCount,
         AVG(p.Score) AS AvgAnswerScore
  FROM Posts p
  WHERE p.PostTypeId = 2
  GROUP BY p.ParentId
)
SELECT us.Id, us.DisplayName, us.CreationDate,
       us.QuestionCount, us.AvgQuestionScore,
       COALESCE(us.PopularTags, 'None') AS TopTags,
       COALESCE(cs.CommentCount, 0) AS CommentCount,
       COALESCE(cs.TotalCommentScore, 0) AS TotalCommentScore,
       COALESCE(bs.BadgeCount, 0) AS BadgeCount,
       COALESCE(bs.GoldBadges, 0) AS GoldBadges,
       COALESCE(bs.SilverBadges, 0) AS SilverBadges,
       COALESCE(bs.BronzeBadges, 0) AS BronzeBadges,
       COALESCE(bs.BadgePoints, 0) AS BadgePoints,
       COALESCE(vs.UpvoteCount, 0) AS UpvoteCount,
       COALESCE(vs.DownvoteCount, 0) AS DownvoteCount,
       COALESCE(vs.TotalBountiesStarted, 0) AS TotalBountiesStarted,
       (SELECT COALESCE(AVG(as2.AvgAnswerScore), 0)
        FROM AnswerStats as2
        WHERE as2.ParentId IN (SELECT p.Id FROM Posts p WHERE p.OwnerUserId = us.Id AND p.PostTypeId = 1)) AS AvgAnswerScoreToMyQuestions,
       (us.QuestionCount * 10 +
        COALESCE(bs.BadgePoints, 0) +
        COALESCE(vs.UpvoteCount, 0) -
        COALESCE(vs.DownvoteCount, 0) +
        (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = us.Id AND ph.PostHistoryTypeId = 5)) AS CompositeScore,
       RANK() OVER (ORDER BY (us.QuestionCount * 10 + COALESCE(bs.BadgePoints, 0) + COALESCE(vs.UpvoteCount, 0) - COALESCE(vs.DownvoteCount, 0)) DESC) AS OverallRank,
       DENSE_RANK() OVER (PARTITION BY EXTRACT(YEAR FROM us.CreationDate) ORDER BY COALESCE(bs.BadgePoints, 0) DESC) AS YearlyBadgeRank
FROM UserStats us
LEFT JOIN CommentStats cs ON us.Id = cs.UserId
LEFT JOIN BadgeStats bs ON us.Id = bs.UserId
LEFT JOIN VoteStats vs ON us.Id = vs.UserId
WHERE us.QuestionCount > 0
   OR COALESCE(bs.BadgeCount, 0) > 0
   OR COALESCE(vs.UpvoteCount, 0) > 10
ORDER BY OverallRank, YearlyBadgeRank
LIMIT 100;
