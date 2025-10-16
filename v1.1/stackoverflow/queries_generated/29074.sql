-- {"query": "29074.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3545} 
WITH UserActivityStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(c.CreationDate) AS LastCommentDate,
        MAX(v.CreationDate) AS LastVoteDate,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 THEN 
                DATEDIFF(CURRENT_TIMESTAMP, MIN(p.CreationDate))
            ELSE NULL 
        END AS DaysSinceFirstPost,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 THEN 
                CAST(AVG(p.Score) AS DECIMAL(10,2))
            ELSE NULL 
        END AS AvgPostScore,
        STRING_AGG(DISTINCT COALESCE(p.Tags, ''), ', ') AS AllTags,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS PostRank,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
        RANK() OVER (ORDER BY COUNT(DISTINCT v.Id) DESC) AS VoteRank,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT b.Id) DESC) AS BadgeRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.Id > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
TopUsers AS (
    SELECT 
        *,
        CASE 
            WHEN PostCount > 100 THEN 'Veteran'
            WHEN PostCount > 50 THEN 'Experienced'
            WHEN PostCount > 10 THEN 'Intermediate'
            ELSE 'Beginner'
        END AS UserLevel,
        CASE 
            WHEN Reputation > 10000 THEN 'Elite'
            WHEN Reputation > 5000 THEN 'Expert'
            WHEN Reputation > 1000 THEN 'Advanced'
            ELSE 'Novice'
        END AS ReputationTier
    FROM UserActivityStats
    WHERE PostCount >= 1
),
UserPostAnalysis AS (
    SELECT 
        tu.UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.PostCount,
        tu.CommentCount,
        tu.BadgeCount,
        tu.VoteCount,
        tu.PostRank,
        tu.ReputationRank,
        tu.VoteRank,
        tu.BadgeRank,
        tu.UserLevel,
        tu.ReputationTier,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        MAX(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS MaxQuestionScore,
        MAX(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS MaxAnswerScore,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgAnswerScore,
        COUNT(DISTINCT CASE WHEN p.Score > 10 THEN p.Id END) AS HighScoringPosts,
        COUNT(DISTINCT CASE WHEN p.ViewCount > 100 THEN p.Id END) AS HighlyViewedPosts,
        COUNT(DISTINCT CASE WHEN p.CommentCount > 5 THEN p.Id END) AS CommentedPosts,
        COUNT(DISTINCT CASE WHEN p.FavoriteCount > 0 THEN p.Id END) AS FavoritedPosts,
        STRING_AGG(CASE WHEN p.PostTypeId = 1 THEN p.Title END, '; ') AS QuestionTitles,
        STRING_AGG(CASE WHEN p.PostTypeId = 2 THEN p.Body END, ' | ') AS AnswerBodies,
        COUNT(DISTINCT CASE WHEN EXISTS (
            SELECT 1 FROM PostHistory ph 
            WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (1, 2, 3)
        ) THEN p.Id END) AS EditedPosts
    FROM TopUsers tu
    LEFT JOIN Posts p ON tu.UserId = p.OwnerUserId
    WHERE p.Id IS NOT NULL
    GROUP BY tu.UserId, tu.DisplayName, tu.Reputation, tu.PostCount, 
             tu.CommentCount, tu.BadgeCount, tu.VoteCount, tu.PostRank, 
             tu.ReputationRank, tu.VoteRank, tu.BadgeRank, tu.UserLevel, 
             tu.ReputationTier
),
UserEngagementMetrics AS (
    SELECT 
        upa.UserId,
        upa.DisplayName,
        upa.Reputation,
        upa.PostCount,
        upa.QuestionCount,
        upa.AnswerCount,
        upa.MaxQuestionScore,
        upa.MaxAnswerScore,
        upa.AvgQuestionScore,
        upa.AvgAnswerScore,
        upa.HighScoringPosts,
        upa.HighlyViewedPosts,
        upa.CommentedPosts,
        upa.FavoritedPosts,
        upa.QuestionTitles,
        upa.AnswerBodies,
        upa.EditedPosts,
        upa.UserLevel,
        upa.ReputationTier,
        upa.PostRank,
        upa.ReputationRank,
        upa.VoteRank,
        upa.BadgeRank,
        CASE 
            WHEN upa.QuestionCount > 0 THEN 
                (CAST(upa.AnswerCount AS FLOAT) / CAST(upa.QuestionCount AS FLOAT)) * 100
            ELSE 0 
        END AS AnswerQuestionRatio,
        CASE 
            WHEN upa.HighScoringPosts > 0 THEN 
                (CAST(upa.HighlyViewedPosts AS FLOAT) / CAST(upa.HighScoringPosts AS FLOAT)) * 100
            ELSE 0 
        END AS ViewToScoreRatio,
        CASE 
            WHEN upa.PostCount > 0 THEN 
                (CAST(upa.CommentCount AS FLOAT) / CAST(upa.PostCount AS FLOAT)) * 100
            ELSE 0 
        END AS CommentPerPostRatio,
        CASE 
            WHEN upa.PostCount > 0 THEN 
                (CAST(upa.BadgeCount AS FLOAT) / CAST(upa.PostCount AS FLOAT)) * 100
            ELSE 0 
        END AS BadgePerPostRatio,
        CASE 
            WHEN upa.PostCount > 0 THEN 
                CAST(upa.VoteCount AS FLOAT) / CAST(upa.PostCount AS FLOAT)
            ELSE 0 
        END AS VotesPerPost,
        DENSE_RANK() OVER (ORDER BY upa.AnswerQuestionRatio DESC) AS AnswerRatioRank,
        DENSE_RANK() OVER (ORDER BY upa.ViewToScoreRatio DESC) AS ViewScoreRatioRank,
        DENSE_RANK() OVER (ORDER BY upa.CommentPerPostRatio DESC) AS CommentRatioRank,
        DENSE_RANK() OVER (ORDER BY upa.BadgePerPostRatio DESC) AS BadgeRatioRank
    FROM UserPostAnalysis upa
),
ComplexActivityAnalysis AS (
    SELECT 
        uem.UserId,
        uem.DisplayName,
        uem.Reputation,
        uem.PostCount,
        uem.QuestionCount,
        uem.AnswerCount,
        uem.MaxQuestionScore,
        uem.MaxAnswerScore,
        uem.AvgQuestionScore,
        uem.AvgAnswerScore,
        uem.HighScoringPosts,
        uem.HighlyViewedPosts,
        uem.CommentedPosts,
        uem.FavoritedPosts,
        uem.QuestionTitles,
        uem.AnswerBodies,
        uem.EditedPosts,
        uem.UserLevel,
        uem.ReputationTier,
        uem.PostRank,
        uem.ReputationRank,
        uem.VoteRank,
        uem.BadgeRank,
        uem.AnswerQuestionRatio,
        uem.ViewToScoreRatio,
        uem.CommentPerPostRatio,
        uem.BadgePerPostRatio,
        uem.VotesPerPost,
        uem.AnswerRatioRank,
        uem.ViewScoreRatioRank,
        uem.CommentRatioRank,
        uem.BadgeRatioRank,
        CASE 
            WHEN uem.ReputationRank <= 50 THEN 'Top Tier'
            WHEN uem.ReputationRank <= 200 THEN 'High Tier'
            WHEN uem.ReputationRank <= 500 THEN 'Medium Tier'
            ELSE 'Lower Tier'
        END AS ReputationBucket,
        CASE 
            WHEN uem.PostRank <= 50 THEN 'Highly Active'
            WHEN uem.PostRank <= 200 THEN 'Active'
            WHEN uem.PostRank <= 500 THEN 'Moderate'
            ELSE 'Less Active'
        END AS ActivityBucket,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) OVER (PARTITION BY uem.UserId) AS UserQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) OVER (PARTITION BY uem.UserId) AS UserAnswers,
        ROW_NUMBER() OVER (ORDER BY uem.PostCount DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativePostCount,
        AVG(uem.HighestScore) OVER (ORDER BY uem.Reputation DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeAvgReputation,
        MAX(uem.PostCount) OVER () AS TotalUserPosts,
        COALESCE(
            (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = uem.UserId AND p2.PostTypeId = 1 AND p2.CreationDate >= DATEADD(year, -1, CURRENT_TIMESTAMP)), 
            0
        ) AS RecentQuestions,
        COALESCE(
            (SELECT COUNT(*) FROM Posts p3 WHERE p3.OwnerUserId = uem.UserId AND p3.PostTypeId = 2 AND p3.CreationDate >= DATEADD(year, -1, CURRENT_TIMESTAMP)), 
            0
        ) AS RecentAnswers,
        COALESCE(
            (SELECT MAX(p4.Score) FROM Posts p4 WHERE p4.OwnerUserId = uem.UserId AND p4.PostTypeId = 1), 
            0
        ) AS MaxQuestionScoreByUser,
        COALESCE(
            (SELECT MAX(p5.Score) FROM Posts p5 WHERE p5.OwnerUserId = uem.UserId AND p5.PostTypeId = 2), 
            0
        ) AS MaxAnswerScoreByUser,
        CASE 
            WHEN uem.PostCount > (SELECT AVG(Posts.Count) FROM (SELECT COUNT(*) AS Count FROM Posts GROUP BY OwnerUserId) Posts) 
                AND uem.Reputation > (SELECT AVG(Reputation) FROM Users) 
                AND uem.VoteCount > (SELECT AVG(VoteCount) FROM UserActivityStats)
            THEN 'Above Average'
            ELSE 'Below Average'
        END AS PerformanceStatus,
        COALESCE(
            (SELECT STRING_AGG(CONCAT(b.Name, ' (', b.Class, ')'), ', ') 
             FROM Badges b 
             WHERE b.UserId = uem.UserId 
             AND b.Class = 1), 
            'No Gold Badges'
        ) AS GoldBadges,
        COALESCE(
            (SELECT STRING_AGG(CONCAT(b.Name, ' (', b.Class, ')'), ', ') 
             FROM Badges b 
             WHERE b.UserId = uem.UserId 
             AND b.Class = 2), 
            'No Silver Badges'
        ) AS SilverBadges,
        COALESCE(
            (SELECT STRING_AGG(CONCAT(b.Name, ' (', b.Class, ')'), ', ') 
             FROM Badges b 
             WHERE b.UserId = uem.UserId 
             AND b.Class = 3), 
            'No Bronze Badges'
        ) AS BronzeBadges
    FROM UserEngagementMetrics uem
    LEFT JOIN Posts p ON uem.UserId = p.OwnerUserId
    LEFT JOIN (
        SELECT OwnerUserId, MAX(Score) AS HighestScore
        FROM Posts
        GROUP BY OwnerUserId
    ) max_scores ON uem.UserId = max_scores.OwnerUserId
    WHERE uem.UserId IN (SELECT UserId FROM UserActivityStats WHERE PostCount >= 1)
),
FinalAnalysis AS (
    SELECT 
        *,
        CASE 
            WHEN PostCount >= 500 THEN 'Elite Contributor'
            WHEN PostCount >= 200 THEN 'Senior Contributor'
            WHEN PostCount >= 100 THEN 'Contributor'
            WHEN PostCount >= 50 THEN 'Active Member'
            ELSE 'Member'
        END AS ContributionLevel,
        CASE 
            WHEN Reputation >= 10000 THEN 'Legend'
            WHEN Reputation >= 5000 THEN 'Master'
            WHEN Reputation >= 1000 THEN 'Veteran'
            WHEN Reputation >= 500 THEN 'Advanced Member'
            ELSE 'Regular Member'
        END AS ReputationLevel,
        CASE 
            WHEN AnswerCount > 0 AND QuestionCount > 0 THEN 
                CASE 
                    WHEN AnswerQuestionRatio > 100 THEN 'More Answers Than Questions'
                    WHEN AnswerQuestionRatio > 50 THEN 'Equal Answers to Questions'
                    ELSE 'Fewer Answers Than Questions'
                END
            ELSE 'No Answer Data'
        END AS AnswerQuestionTrend
    FROM ComplexActivityAnalysis
)
SELECT 
    fa.UserId,
    fa.DisplayName,
    fa.Reputation,
    fa.PostCount,
    fa.QuestionCount,
    fa.AnswerCount,
    fa.MaxQuestionScore,
    fa.MaxAnswerScore,
    fa.AvgQuestionScore,
    fa.AvgAnswerScore,
    fa.HighScoringPosts,
    fa.HighlyViewedPosts,
    fa.CommentedPosts,
    fa.FavoritedPosts,
    fa.UserLevel,
    fa.ReputationTier,
    fa.ReputationBucket,
    fa.ActivityBucket,
    fa.AnswerQuestionRatio,
    fa.ViewToScoreRatio,
    fa.CommentPerPostRatio,
    fa.BadgePerPostRatio,
    fa.VotesPerPost,
    fa.PerformanceStatus,
    fa.ContributionLevel,
    fa.ReputationLevel,
    fa.AnswerQuestionTrend,
    CAST((PostCount * 100.0 / (SELECT SUM(PostCount) FROM FinalAnalysis)) AS DECIMAL(5,2)) AS PostPercentage,
    RANK() OVER (ORDER BY PostCount DESC) AS PostRankByCount,
    DENSE_RANK() OVER (ORDER BY Reputation DESC) AS ReputationRankByScore,
    ROW_NUMBER() OVER (ORDER BY PostCount DESC, Reputation DESC) AS OverallRank,
    CASE 
        WHEN PostCount >= 1000 AND Reputation >= 5000 THEN 'Top Performer'
        WHEN PostCount >= 500 AND Reputation >= 2500 THEN 'High Performer'
        WHEN PostCount >= 100 AND Reputation >= 1000 THEN 'Good Performer'
        ELSE 'Standard Performer'
    END AS PerformanceCategory,
    STRING_AGG(
        CONCAT(
            p.Title, 
            ' (', 
            CASE WHEN p.PostTypeId = 1 THEN 'Question' ELSE 'Answer' END,
            ', Score: ', p.Score, 
            ', Views: ', p.ViewCount, 
            ', Tags: ', COALESCE(p.Tags, 'None')
        ), 
        ' | '
    ) AS RecentPostDetails,
    COUNT(DISTINCT p.Id) AS RecentPostCount
FROM FinalAnalysis fa
LEFT JOIN Posts p ON fa.UserId = p.OwnerUserId
WHERE fa.UserId IN (SELECT UserId FROM UserActivityStats WHERE PostCount >= 10)
GROUP BY 
    fa.UserId, fa.DisplayName, fa.Reputation, fa.PostCount, 
    fa.QuestionCount, fa.AnswerCount, fa.MaxQuestionScore, 
    fa.MaxAnswerScore, fa.AvgQuestionScore, fa.AvgAnswerScore, 
    fa.HighScoringPosts, fa.HighlyViewedPosts, fa.CommentedPosts, 
    fa.FavoritedPosts, fa.UserLevel, fa.ReputationTier, 
    fa.ReputationBucket, fa.ActivityBucket, fa.AnswerQuestionRatio, 
    fa.ViewToScoreRatio, fa.CommentPerPostRatio, fa.BadgePerPostRatio, 
    fa.VotesPerPost, fa.PerformanceStatus, fa.ContributionLevel, 
    fa.ReputationLevel, fa.AnswerQuestionTrend
HAVING COUNT(DISTINCT p.Id) > 0
ORDER BY fa.PostCount DESC, fa.Reputation DESC
LIMIT 1000;