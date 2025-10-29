-- {"query": "7783.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1505} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as PostRank,
        RANK() OVER (ORDER BY u.Reputation DESC) as RepRank,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 100 THEN 'High Engager'
            WHEN COUNT(DISTINCT p.Id) > 50 THEN 'Medium Engager'
            WHEN COUNT(DISTINCT p.Id) > 10 THEN 'Low Engager'
            ELSE 'Newcomer'
        END as EngagementLevel
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.AccountId IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
HighValuePosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Tags,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostType,
        COALESCE(p.AnswerCount, 0) as AnswerCount,
        COALESCE(p.CommentCount, 0) as CommentCount,
        COALESCE(p.FavoriteCount, 0) as FavoriteCount,
        CASE 
            WHEN p.Score > 100 THEN 'High'
            WHEN p.Score > 50 THEN 'Medium'
            WHEN p.Score > 10 THEN 'Low'
            ELSE 'Very Low'
        END as ScoreCategory,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) as ScoreRank
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) 
        AND p.Score > 0
        AND p.ViewCount > 10
),
UserPostPerformance AS (
    SELECT 
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.PostCount,
        uas.CommentCount,
        uas.BadgeCount,
        uas.PostRank,
        uas.RepRank,
        uas.EngagementLevel,
        hvp.PostTypeId,
        hvp.Title,
        hvp.Score,
        hvp.ViewCount,
        hvp.CreationDate,
        hvp.Tags,
        hvp.PostType,
        hvp.AnswerCount,
        hvp.CommentCount,
        hvp.FavoriteCount,
        hvp.ScoreCategory,
        hvp.ScoreRank,
        ROW_NUMBER() OVER (PARTITION BY uas.UserId ORDER BY hvp.Score DESC) as TopPostRank
    FROM UserActivityStats uas
    INNER JOIN HighValuePosts hvp ON uas.UserId = hvp.OwnerUserId
    WHERE uas.PostCount > 0
),
ComplexStats AS (
    SELECT 
        upp.UserId,
        upp.DisplayName,
        upp.Reputation,
        upp.PostCount,
        upp.CommentCount,
        upp.BadgeCount,
        upp.PostRank,
        upp.RepRank,
        upp.EngagementLevel,
        COUNT(*) as TotalHighValuePosts,
        AVG(upp.Score) as AvgScore,
        MAX(upp.Score) as MaxScore,
        MIN(upp.Score) as MinScore,
        SUM(upp.FavoriteCount) as TotalFavorites,
        STRING_AGG(upp.Tags, '; ') as AllTags,
        STRING_AGG(UPPER(LEFT(upp.Title, 30)), ' | ') as SampleTitles,
        (COUNT(*) * AVG(upp.Score)) as WeightedScore,
        CASE 
            WHEN AVG(upp.Score) > 50 THEN 'Consistent Top Performer'
            WHEN AVG(upp.Score) > 20 THEN 'Moderate Performer'
            ELSE 'Occasional Performer'
        END as PerformanceLevel,
        ROW_NUMBER() OVER (ORDER BY COUNT(*) * AVG(upp.Score) DESC) as OverallRank
    FROM UserPostPerformance upp
    GROUP BY upp.UserId, upp.DisplayName, upp.Reputation, upp.PostCount, upp.CommentCount, upp.BadgeCount, upp.PostRank, upp.RepRank, upp.EngagementLevel
    HAVING COUNT(*) >= 2
)
SELECT 
    cs.UserId,
    cs.DisplayName,
    cs.Reputation,
    cs.PostCount,
    cs.CommentCount,
    cs.BadgeCount,
    cs.PostRank,
    cs.RepRank,
    cs.EngagementLevel,
    cs.TotalHighValuePosts,
    ROUND(cs.AvgScore, 2) as AvgScore,
    cs.MaxScore,
    cs.MinScore,
    cs.TotalFavorites,
    cs.AllTags,
    cs.SampleTitles,
    ROUND(cs.WeightedScore, 2) as WeightedScore,
    cs.PerformanceLevel,
    cs.OverallRank,
    CASE 
        WHEN cs.MaxScore >= 500 THEN 'Legend'
        WHEN cs.MaxScore >= 100 THEN 'Elite'
        WHEN cs.MaxScore >= 50 THEN 'Experienced'
        WHEN cs.MaxScore >= 20 THEN 'Competent'
        ELSE 'Novice'
    END as AchievementTier,
    (SELECT COUNT(*) FROM Users u WHERE u.Reputation > cs.Reputation) as ReputationRankBelow,
    (SELECT COUNT(*) FROM Users u WHERE u.Reputation < cs.Reputation) as ReputationRankAbove,
    (CASE WHEN cs.WeightedScore > (SELECT AVG(WeightedScore) FROM ComplexStats) THEN 1 ELSE 0 END) as AboveAvgPerformance,
    (SELECT String_Agg(Title, ', ') FROM (
        SELECT Title FROM UserPostPerformance upp2 
        WHERE upp2.UserId = cs.UserId 
        AND upp2.Score = cs.MaxScore
        LIMIT 1
    )) as TopScoringPostTitle,
    LAG(cs.ScoreRank) OVER (ORDER BY cs.UserId) as PreviousUserScoreRank,
    LEAD(cs.ScoreRank) OVER (ORDER BY cs.UserId) as NextUserScoreRank,
    ABS(cs.ScoreRank - LAG(cs.ScoreRank) OVER (ORDER BY cs.UserId)) as RankDifferenceFromPrevious,
    NTILE(10) OVER (ORDER BY cs.WeightedScore) as PerformanceDecile,
    (CASE 
        WHEN cs.PostCount > 50 AND cs.BadgeCount > 10 THEN 'Active Contributor'
        WHEN cs.PostCount > 20 AND cs.BadgeCount > 5 THEN 'Regular Participant'
        ELSE 'Occasional Participant'
    END) as ContributionStatus
FROM ComplexStats cs
WHERE cs.OverallRank <= 100
ORDER BY cs.WeightedScore DESC, cs.Reputation DESC, cs.PostCount DESC
LIMIT 50;