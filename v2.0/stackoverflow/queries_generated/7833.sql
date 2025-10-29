-- {"query": "7833.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2974} 
WITH UserActivity AS (
    SELECT u.Id AS UserId,
           u.DisplayName,
           u.Reputation,
           u.Views,
           u.UpVotes,
           u.DownVotes,
           COUNT(DISTINCT p.Id) AS PostCount,
           COUNT(DISTINCT c.Id) AS CommentCount,
           COUNT(DISTINCT b.Id) AS BadgeCount,
           MAX(p.CreationDate) AS LastPostDate,
           MAX(c.CreationDate) AS LastCommentDate,
           MAX(b.Date) AS LastBadgeDate,
           CASE WHEN u.Views = 0 THEN 'Inactive' WHEN u.Views < 100 THEN 'Low' WHEN u.Views < 1000 THEN 'Medium' ELSE 'High' END AS EngagementLevel
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
PostStats AS (
    SELECT p.Id AS PostId,
           p.Title,
           p.Score,
           p.ViewCount,
           p.AnswerCount,
           p.CommentCount,
           p.FavoriteCount,
           p.CreationDate,
           p.OwnerUserId,
           p.OwnerDisplayName,
           p.LastActivityDate,
           p.Tags,
           p.PostTypeId,
           CASE WHEN p.PostTypeId = 1 THEN 'Question' WHEN p.PostTypeId = 2 THEN 'Answer' ELSE 'Other' END AS PostType,
           DATEDIFF('DAY', p.CreationDate, p.LastActivityDate) AS DaysSinceLastActivity,
           LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousScore,
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostRank,
           CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END AS HasAcceptedAnswer
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
QualityScores AS (
    SELECT ps.PostId,
           ps.Title,
           ps.Score,
           ps.ViewCount,
           ps.AnswerCount,
           ps.CommentCount,
           ps.FavoriteCount,
           ps.PostType,
           ps.DaysSinceLastActivity,
           ps.PreviousScore,
           ps.PostRank,
           ps.HasAcceptedAnswer,
           CASE WHEN ps.Score > 10 THEN 'High' WHEN ps.Score > 5 THEN 'Medium' ELSE 'Low' END AS ScoreCategory,
           CASE WHEN ps.AnswerCount > 5 THEN 'High' WHEN ps.AnswerCount > 2 THEN 'Medium' ELSE 'Low' END AS AnswerQuality,
           CASE WHEN ps.ViewCount > 1000 THEN 'High' WHEN ps.ViewCount > 100 THEN 'Medium' ELSE 'Low' END AS ViewQuality,
           CASE WHEN ps.FavoriteCount > 10 THEN 'High' WHEN ps.FavoriteCount > 5 THEN 'Medium' ELSE 'Low' END AS FavoriteQuality,
           (ps.Score * 0.3 + ps.ViewCount * 0.4 + ps.AnswerCount * 0.2 + ps.FavoriteCount * 0.1) AS CompositeQualityScore,
           CASE 
               WHEN ps.Score >= 10 AND ps.AnswerCount >= 3 AND ps.ViewCount >= 500 THEN 'Excellent'
               WHEN ps.Score >= 5 AND ps.AnswerCount >= 2 AND ps.ViewCount >= 200 THEN 'Good'
               WHEN ps.Score >= 1 AND ps.AnswerCount >= 1 AND ps.ViewCount >= 50 THEN 'Fair'
               ELSE 'Poor'
           END AS QualityRating
    FROM PostStats ps
),
BadgesWithRanking AS (
    SELECT b.Id AS BadgeId,
           b.UserId,
           b.Name,
           b.Date,
           b.Class,
           b.TagBased,
           ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) AS BadgeRank,
           COUNT(*) OVER (PARTITION BY b.UserId) AS TotalBadges,
           CASE 
               WHEN b.Class = 1 THEN 'Gold'
               WHEN b.Class = 2 THEN 'Silver'
               WHEN b.Class = 3 THEN 'Bronze'
               ELSE 'Unknown'
           END AS BadgeTier,
           CASE 
               WHEN b.Name IN ('Autobiographer', 'Good Answer', 'Great Answer', 'Populist', 'Stellar Question') THEN 'Elite'
               WHEN b.Name IN ('Nice Answer', 'Good Question', 'Great Question', 'Popular Question', 'Notable Question') THEN 'Prominent'
               WHEN b.Name IN ('First Answer', 'First Question', 'Student', 'Teacher', 'Scholar') THEN 'Beginner'
               ELSE 'Regular'
           END AS BadgesCategory
    FROM Badges b
),
UserComplexityAnalysis AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.PostCount,
        ua.CommentCount,
        ua.BadgeCount,
        ua.LastPostDate,
        ua.LastCommentDate,
        ua.LastBadgeDate,
        ua.EngagementLevel,
        AVG(ps.Score) AS AveragePostScore,
        MAX(ps.Score) AS MaxPostScore,
        MIN(ps.Score) AS MinPostScore,
        STDDEV(ps.Score) AS ScoreVariance,
        COUNT(CASE WHEN ps.PostType = 'Question' THEN 1 END) AS QuestionCount,
        COUNT(CASE WHEN ps.PostType = 'Answer' THEN 1 END) AS AnswerCount,
        AVG(ps.DaysSinceLastActivity) AS AvgDaysSinceLastActivity,
        SUM(ps.ViewCount) AS TotalViews,
        SUM(ps.AnswerCount) AS TotalAnswers,
        CASE 
            WHEN ua.PostCount > 0 THEN 
                (COUNT(CASE WHEN ps.HasAcceptedAnswer = 1 THEN 1 END) * 100.0 / ua.PostCount)
            ELSE 0 
        END AS AcceptanceRate,
        CASE 
            WHEN ua.BadgeCount > 0 THEN 
                MAX(bwr.BadgeRank) 
            ELSE NULL 
        END AS MostRecentBadgeRank,
        NULLIF(COUNT(CASE WHEN bwr.BadgeTier = 'Gold' THEN 1 END), 0) AS GoldBadgesCount,
        NULLIF(COUNT(CASE WHEN bwr.BadgeTier = 'Silver' THEN 1 END), 0) AS SilverBadgesCount,
        NULLIF(COUNT(CASE WHEN bwr.BadgeTier = 'Bronze' THEN 1 END), 0) AS BronzeBadgesCount,
        STRING_AGG(DISTINCT bwr.BadgesCategory, ', ') WITHIN GROUP (ORDER BY bwr.BadgesCategory) AS BadgeCategories
    FROM UserActivity ua
    LEFT JOIN PostStats ps ON ua.UserId = ps.OwnerUserId
    LEFT JOIN BadgesWithRanking bwr ON ua.UserId = bwr.UserId
    WHERE ua.UserId IS NOT NULL
    GROUP BY ua.UserId, ua.DisplayName, ua.Reputation, ua.PostCount, ua.CommentCount, ua.BadgeCount, 
             ua.LastPostDate, ua.LastCommentDate, ua.LastBadgeDate, ua.EngagementLevel
),
TopPosts AS (
    SELECT 
        ps.PostId,
        ps.Title,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.PostType,
        ps.DaysSinceLastActivity,
        ps.PreviousScore,
        ps.PostRank,
        ps.HasAcceptedAnswer,
        ps.ScoreCategory,
        ps.AnswerQuality,
        ps.ViewQuality,
        ps.FavoriteQuality,
        ps.CompositeQualityScore,
        ps.QualityRating,
        ROW_NUMBER() OVER (ORDER BY ps.CompositeQualityScore DESC) AS GlobalRank,
        DENSE_RANK() OVER (ORDER BY ps.Score DESC) AS ScoreRank,
        DENSE_RANK() OVER (ORDER BY ps.ViewCount DESC) AS ViewRank,
        DENSE_RANK() OVER (ORDER BY ps.AnswerCount DESC) AS AnswerRank,
        DENSE_RANK() OVER (ORDER BY ps.FavoriteCount DESC) AS FavoriteRank
    FROM PostStats ps
),
TopUsers AS (
    SELECT 
        uca.UserId,
        uca.DisplayName,
        uca.Reputation,
        uca.PostCount,
        uca.CommentCount,
        uca.BadgeCount,
        uca.LastPostDate,
        uca.LastCommentDate,
        uca.LastBadgeDate,
        uca.EngagementLevel,
        uca.AveragePostScore,
        uca.MaxPostScore,
        uca.MinPostScore,
        uca.ScoreVariance,
        uca.QuestionCount,
        uca.AnswerCount,
        uca.AvgDaysSinceLastActivity,
        uca.TotalViews,
        uca.TotalAnswers,
        uca.AcceptanceRate,
        uca.MostRecentBadgeRank,
        uca.GoldBadgesCount,
        uca.SilverBadgesCount,
        uca.BronzeBadgesCount,
        uca.BadgeCategories,
        ROW_NUMBER() OVER (ORDER BY uca.Reputation DESC, uca.PostCount DESC, uca.BadgeCount DESC, uca.TotalViews DESC) AS UserRank,
        DENSE_RANK() OVER (ORDER BY uca.AveragePostScore DESC) AS AvgScoreRank,
        DENSE_RANK() OVER (ORDER BY uca.TotalViews DESC) AS TotalViewRank,
        DENSE_RANK() OVER (ORDER BY uca.BadgeCount DESC) AS TotalBadgeRank
    FROM UserComplexityAnalysis uca
)

SELECT 
    tu.UserRank,
    tu.DisplayName,
    tu.Reputation,
    tu.PostCount,
    tu.CommentCount,
    tu.BadgeCount,
    tu.EngagementLevel,
    tu.AveragePostScore,
    tu.MaxPostScore,
    tu.MinPostScore,
    tu.ScoreVariance,
    tu.QuestionCount,
    tu.AnswerCount,
    tu.AvgDaysSinceLastActivity,
    tu.TotalViews,
    tu.TotalAnswers,
    tu.AcceptanceRate,
    tu.GoldBadgesCount,
    tu.SilverBadgesCount,
    tu.BronzeBadgesCount,
    tu.BadgeCategories,
    CASE 
        WHEN tu.UserRank <= 10 THEN 'Top 10'
        WHEN tu.UserRank <= 50 THEN 'Top 50'
        WHEN tu.UserRank <= 100 THEN 'Top 100'
        ELSE 'Other'
    END AS UserRankCategory,
    STRING_AGG(
        CONCAT('PostID:', tp.PostId, ' - Score:', tp.Score, ' - Views:', tp.ViewCount),
        '; '
        ORDER BY tp.CompositeQualityScore DESC
    ) AS TopPostsInfo,
    (SELECT COUNT(*) FROM TopPosts tp2 WHERE tp2.GlobalRank <= 100) AS Top100PostsCount,
    (SELECT AVG(CompositeQualityScore) FROM TopPosts tp3 WHERE tp3.GlobalRank <= 100) AS AvgTop100Score,
    CASE 
        WHEN tu.BadgeCount = 0 THEN 'No Badges'
        WHEN tu.GoldBadgesCount >= 1 THEN 'Gold Medalist'
        WHEN tu.SilverBadgesCount >= 1 THEN 'Silver Medalist'
        WHEN tu.BronzeBadgesCount >= 1 THEN 'Bronze Medalist'
        ELSE 'Regular'
    END AS AchievementTier,
    CASE 
        WHEN tu.Reputation >= 250000 THEN 'Legendary'
        WHEN tu.Reputation >= 100000 THEN 'Master'
        WHEN tu.Reputation >= 25000 THEN 'Expert'
        WHEN tu.Reputation >= 1000 THEN 'Advanced'
        ELSE 'Beginner' 
    END AS ReputationTier,
    COALESCE(
        (SELECT TOP 1 tp4.PostId 
         FROM TopPosts tp4 
         WHERE tp4.GlobalRank <= 10 
         ORDER BY tp4.CompositeQualityScore DESC), 
        0
    ) AS TopRankedPostId,
    (SELECT AVG(Top100PostsCount) FROM (VALUES (100), (200), (300), (400)) AS v(x)) AS DummyAvgCalculation,
    (SELECT COUNT(*) FROM UserActivity ua2 WHERE ua2.PostCount > 0) AS ActiveUsersCount,
    NULLIF(tu.TotalViews, 0) / NULLIF(COUNT(tu.UserId), 0) AS AvgViewsPerActiveUser,
    CAST(SUM(tu.GoldBadgesCount) AS FLOAT) / COUNT(tu.UserId) AS AvgGoldBadgesPerUser,
    CASE WHEN tu.UserRank % 2 = 0 THEN 'Even' ELSE 'Odd' END AS RankParity,
    ABS(tu.Reputation - (SELECT AVG(Reputation) FROM Users)) AS ReputationDeviationFromMean
FROM TopUsers tu
LEFT JOIN TopPosts tp ON tp.GlobalRank <= 5
WHERE tu.UserRank <= 100
GROUP BY 
    tu.UserRank,
    tu.DisplayName,
    tu.Reputation,
    tu.PostCount,
    tu.CommentCount,
    tu.BadgeCount,
    tu.EngagementLevel,
    tu.AveragePostScore,
    tu.MaxPostScore,
    tu.MinPostScore,
    tu.ScoreVariance,
    tu.QuestionCount,
    tu.AnswerCount,
    tu.AvgDaysSinceLastActivity,
    tu.TotalViews,
    tu.TotalAnswers,
    tu.AcceptanceRate,
    tu.GoldBadgesCount,
    tu.SilverBadgesCount,
    tu.BronzeBadgesCount,
    tu.BadgeCategories,
    tu.UserRank,
    tu.Reputation
HAVING 
    COUNT(tu.UserId) > 0
ORDER BY
    CASE WHEN tu.UserRank <= 10 THEN 0 ELSE 1 END,
    tu.Reputation DESC,
    tu.PostCount DESC,
    tu.BadgeCount DESC
OPTION (MAXDOP 4);