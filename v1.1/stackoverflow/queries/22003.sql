WITH UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(COUNT(p.Id), 0) AS TotalPosts,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) AS QuestionScore,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) AS AnswerScore,
        COALESCE(AVG(p.Score), 0) AS AvgPostScore,
        COALESCE(MAX(p.Score), 0) AS MaxPostScore,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedQuestionsCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId IN (1, 2)
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
UserBadgeStats AS (
    SELECT 
        u.Id AS UserId,
        COALESCE(COUNT(b.Id), 0) AS TotalBadges,
        COALESCE(SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END), 0) AS GoldBadges,
        COALESCE(SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END), 0) AS SilverBadges,
        COALESCE(SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END), 0) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id
),
CombinedStats AS (
    SELECT 
        COALESCE(ups.UserId, ubs.UserId) AS UserId,
        ups.DisplayName,
        COALESCE(ups.Reputation, 0) AS Reputation,
        COALESCE(ups.TotalPosts, 0) AS TotalPosts,
        COALESCE(ups.QuestionScore, 0) AS QuestionScore,
        COALESCE(ups.AnswerScore, 0) AS AnswerScore,
        COALESCE(ups.AvgPostScore, 0) AS AvgPostScore,
        COALESCE(ups.MaxPostScore, 0) AS MaxPostScore,
        COALESCE(ups.AcceptedQuestionsCount, 0) AS AcceptedQuestionsCount,
        COALESCE(ubs.TotalBadges, 0) AS TotalBadges,
        COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
        COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
        COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
        ubs.LastBadgeDate,
        (COALESCE(ups.QuestionScore, 0) + COALESCE(ups.AnswerScore, 0)) * 1.0 / NULLIF(COALESCE(ups.TotalPosts, 0), 0) AS WeightedScorePerPost,
        CASE 
            WHEN COALESCE(ubs.TotalBadges, 0) = 0 THEN 0
            ELSE ROUND(COALESCE(ubs.GoldBadges, 0) * 10 + COALESCE(ubs.SilverBadges, 0) * 5 + COALESCE(ubs.BronzeBadges, 0) * 1, 2)
        END AS BadgeScore
    FROM UserPostStats ups
    FULL OUTER JOIN UserBadgeStats ubs ON ups.UserId = ubs.UserId
),
RankedStats AS (
    SELECT 
        cs.UserId,
        cs.DisplayName,
        cs.Reputation,
        cs.TotalPosts,
        cs.QuestionScore,
        cs.AnswerScore,
        cs.AvgPostScore,
        cs.MaxPostScore,
        cs.AcceptedQuestionsCount,
        cs.TotalBadges,
        cs.GoldBadges,
        cs.SilverBadges,
        cs.BronzeBadges,
        cs.LastBadgeDate,
        cs.WeightedScorePerPost,
        cs.BadgeScore,
        ROW_NUMBER() OVER (ORDER BY cs.BadgeScore DESC, cs.WeightedScorePerPost DESC) AS OverallRank,
        RANK() OVER (PARTITION BY cs.Reputation ORDER BY cs.TotalBadges DESC) AS BadgeRankByRep,
        DENSE_RANK() OVER (ORDER BY cs.AcceptedQuestionsCount DESC) AS AcceptedRank,
        LAG(cs.TotalBadges, 1, 0) OVER (ORDER BY cs.UserId) AS PrevUserBadges,
        LEAD(cs.MaxPostScore, 1, 0) OVER (ORDER BY cs.UserId DESC) AS NextUserMaxScore
    FROM CombinedStats cs
    WHERE COALESCE(cs.TotalPosts, 0) > 0 OR COALESCE(cs.TotalBadges, 0) > 0
),
UserActivity AS (
    SELECT 
        rs.UserId,
        rs.DisplayName,
        rs.OverallRank,
        rs.BadgeRankByRep,
        rs.AcceptedRank,
        rs.PrevUserBadges,
        rs.NextUserMaxScore,
        COALESCE(rs.WeightedScorePerPost, 0) AS ScorePerPost,
        rs.BadgeScore,
        rs.AcceptedQuestionsCount,
        rs.TotalBadges,
        CASE 
            WHEN rs.AcceptedQuestionsCount > 0 THEN 'Active Acceptor'
            WHEN rs.TotalBadges >= 10 THEN 'Badge Collector'
            ELSE 'Casual User'
        END AS UserCategory,
        (SELECT 'Has ' || COUNT(*) || ' comments on own posts'
         FROM Comments c
         WHERE c.UserId = rs.UserId AND c.PostId IN (SELECT p.Id FROM Posts p WHERE p.OwnerUserId = rs.UserId)
        ) AS SelfCommentInfo
    FROM RankedStats rs
)
SELECT 
    ua.UserId,
    ua.DisplayName,
    ua.OverallRank,
    ua.BadgeRankByRep,
    ua.AcceptedRank,
    ua.PrevUserBadges,
    ua.NextUserMaxScore,
    ua.ScorePerPost,
    ua.BadgeScore,
    ua.UserCategory,
    ua.SelfCommentInfo,
    CASE 
        WHEN ua.ScorePerPost > 10 THEN 'High Scorer'
        WHEN ua.ScorePerPost BETWEEN 5 AND 10 THEN 'Moderate Scorer'
        ELSE 'Low Scorer'
    END AS ScoringTier,
    SUBSTR(ua.DisplayName, 1, CASE WHEN POSITION(' ' IN ua.DisplayName) = 0 THEN LENGTH(ua.DisplayName) ELSE POSITION(' ' IN ua.DisplayName) - 1 END) AS FirstName,
    ua.ScorePerPost * ua.BadgeScore AS CompositeMetric
FROM UserActivity ua
WHERE ua.UserId IN (
    SELECT u.Id FROM Users u WHERE u.Reputation > 100
    UNION
    SELECT DISTINCT b.UserId FROM Badges b WHERE b.Name LIKE '%top%'
)
ORDER BY ua.OverallRank, (ua.ScorePerPost * ua.BadgeScore) DESC
LIMIT 100;