-- {"query": "7883.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2199} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        CASE 
            WHEN u.Reputation >= 10000 THEN 'Elite'
            WHEN u.Reputation >= 1000 THEN 'Advanced'
            WHEN u.Reputation >= 100 THEN 'Intermediate'
            ELSE 'Beginner'
        END as ReputationTier,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        COALESCE(AVG(p.Score), 0) as AvgScore,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2) FILTER (WHERE p.Tags IS NOT NULL), ', ') as AllTags,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
PostPerformanceMetrics AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.LastActivityDate,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        p.Tags,
        p.PostTypeId,
        COALESCE(p.AnswerCount, 0) as AnswerCountCorrected,
        COALESCE(p.CommentCount, 0) as CommentCountCorrected,
        CASE 
            WHEN p.Score > 100 THEN 'HighlyVoted'
            WHEN p.Score > 50 THEN 'Popular'
            WHEN p.Score > 10 THEN 'Moderate'
            ELSE 'Low'
        END as PopularityLevel,
        DATEDIFF(day, p.CreationDate, p.LastActivityDate) as DaysSinceCreation,
        DATEDIFF(day, p.CreationDate, GETDATE()) as DaysActive,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) as ScoreRank,
        DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) as ViewRank,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) as NewestPost,
        LAG(p.Score, 1) OVER (ORDER BY p.CreationDate) as PrevScore,
        LEAD(p.ViewCount, 1) OVER (ORDER BY p.CreationDate) as NextView,
        AVG(p.Score) OVER (PARTITION BY p.PostTypeId) as AvgPostTypeScore,
        SUM(p.Score) OVER (ORDER BY p.CreationDate) as CumulativeScore,
        NTILE(4) OVER (ORDER BY p.ViewCount) as QuartileViews,
        COALESCE(p.AnswerCount, 0) * 100.0 / NULLIF(p.ViewCount, 0) as AnswerRatioToViews
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2)
),
CombinedAnalysis AS (
    SELECT 
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.PostCount,
        uas.CommentCount,
        uas.BadgeCount,
        uas.TotalScore,
        uas.AvgScore,
        uas.ReputationTier,
        ppm.PostId,
        ppm.Title,
        ppm.Score,
        ppm.ViewCount,
        ppm.AnswerCountCorrected,
        ppm.CommentCountCorrected,
        ppm.FavoriteCount,
        ppm.CreationDate,
        ppm.PopularityLevel,
        ppm.DaysSinceCreation,
        ppm.DaysActive,
        ppm.ScoreRank,
        ppm.ViewRank,
        ppm.AnswerRatioToViews,
        CASE 
            WHEN ppm.Score > 100 AND ppm.ViewCount > 1000 THEN 'Trending'
            WHEN ppm.Score > 50 AND ppm.ViewCount > 500 THEN 'Popular'
            ELSE 'Regular'
        END as TrendStatus,
        CASE 
            WHEN ppm.DaysActive > 365 THEN 'Veteran'
            WHEN ppm.DaysActive > 180 THEN 'Active'
            WHEN ppm.DaysActive > 30 THEN 'Recent'
            ELSE 'New'
        END as ActivityStatus,
        RANK() OVER (PARTITION BY uas.UserId ORDER BY ppm.Score DESC) as UserPostRank,
        DENSE_RANK() OVER (ORDER BY ppm.Score DESC) as GlobalPostRank,
        ROW_NUMBER() OVER (ORDER BY ppm.CreationDate DESC) as ChronologicalPostOrder
    FROM UserActivityStats uas
    JOIN PostPerformanceMetrics ppm ON uas.UserId = ppm.OwnerUserId
    WHERE uas.PostCount > 0
)
SELECT 
    ca.UserId,
    ca.DisplayName,
    ca.Reputation,
    ca.PostCount,
    ca.CommentCount,
    ca.BadgeCount,
    ca.TotalScore,
    ca.AvgScore,
    ca.ReputationTier,
    ca.PostId,
    ca.Title,
    ca.Score,
    ca.ViewCount,
    ca.AnswerCountCorrected,
    ca.CommentCountCorrected,
    ca.FavoriteCount,
    ca.CreationDate,
    ca.PopularityLevel,
    ca.DaysSinceCreation,
    ca.DaysActive,
    ca.ScoreRank,
    ca.ViewRank,
    ca.AnswerRatioToViews,
    ca.TrendStatus,
    ca.ActivityStatus,
    ca.UserPostRank,
    ca.GlobalPostRank,
    ca.ChronologicalPostOrder,
    CASE 
        WHEN ca.Score > (SELECT AVG(Score) FROM PostPerformanceMetrics) THEN 'AboveAverage'
        ELSE 'BelowAverage'
    END as ScorePerformance,
    CASE 
        WHEN ca.ViewCount > (SELECT AVG(ViewCount) FROM PostPerformanceMetrics) THEN 'AboveAverageViews'
        ELSE 'BelowAverageViews'
    END as ViewPerformance,
    CASE 
        WHEN ca.AnswerCountCorrected > 0 THEN CAST(ca.AnswerRatioToViews AS DECIMAL(5,2))
        ELSE 0
    END as AnswerViewRatio,
    COALESCE(
        (SELECT COUNT(*) FROM Posts p2 
         WHERE p2.OwnerUserId = ca.UserId 
         AND p2.ParentId IS NOT NULL 
         AND p2.LastActivityDate > DATEADD(day, -30, GETDATE())), 0
    ) as RecentAnswersCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = ca.PostId AND v.VoteTypeId = 2) as UpvoteCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = ca.PostId AND v.VoteTypeId = 3) as DownvoteCount,
    CASE 
        WHEN ca.PostId IN (
            SELECT DISTINCT PostId FROM PostHistory ph 
            WHERE ph.PostHistoryTypeId IN (10, 11, 12, 13) 
            AND ph.CreationDate > DATEADD(day, -90, GETDATE())
        ) THEN 'RecentlyModified'
        ELSE 'Stable'
    END as ModificationStatus,
    CASE 
        WHEN ca.ReputationTier IN ('Elite', 'Advanced') AND ca.PostCount >= 100 THEN 'EstablishedContributor'
        WHEN ca.ReputationTier IN ('Elite', 'Advanced') THEN 'HighReputationUser'
        WHEN ca.BadgeCount > 20 THEN 'BadgeMaster'
        ELSE 'RegularUser'
    END as UserClassification,
    CASE 
        WHEN ca.Score > 0 AND ca.ViewCount > 0 THEN ROUND(CAST(ca.Score AS FLOAT) / CAST(ca.ViewCount AS FLOAT) * 100, 2)
        ELSE 0
    END as ScoreToViewRatio,
    CASE 
        WHEN ca.PostCount > (SELECT AVG(PostCount) FROM UserActivityStats) THEN 'HighActivityUser'
        ELSE 'NormalActivityUser'
    END as UserActivityLevel,
    STRING_AGG(
        CASE 
            WHEN ca.Title IS NOT NULL THEN SUBSTRING(ca.Title, 1, 50)
            ELSE 'NoTitle'
        END, ', '
    ) WITHIN GROUP (ORDER BY ca.CreationDate DESC) as RecentTitles,
    MAX(CASE WHEN ca.PopularityLevel = 'HighlyVoted' THEN 1 ELSE 0 END) as HasHighlyVotedPost,
    COUNT(DISTINCT CASE WHEN ca.DaysActive < 30 THEN 1 END) as RecentActivityCount,
    COUNT(DISTINCT CASE WHEN ca.ActivityStatus = 'Veteran' THEN 1 END) as VeteranPostCount,
    RANK() OVER (ORDER BY ca.TotalScore DESC) as ScoreRankOverall,
    DENSE_RANK() OVER (ORDER BY ca.PostCount DESC) as PostCountRank
FROM CombinedAnalysis ca
GROUP BY 
    ca.UserId, ca.DisplayName, ca.Reputation, ca.PostCount, ca.CommentCount, 
    ca.BadgeCount, ca.TotalScore, ca.AvgScore, ca.ReputationTier, ca.PostId, 
    ca.Title, ca.Score, ca.ViewCount, ca.AnswerCountCorrected, ca.CommentCountCorrected,
    ca.FavoriteCount, ca.CreationDate, ca.PopularityLevel, ca.DaysSinceCreation,
    ca.DaysActive, ca.ScoreRank, ca.ViewRank, ca.AnswerRatioToViews, ca.TrendStatus,
    ca.ActivityStatus, ca.UserPostRank, ca.GlobalPostRank, ca.ChronologicalPostOrder
HAVING 
    COUNT(*) > 0 AND 
    COUNT(DISTINCT ca.PostId) > 0 AND
    COUNT(DISTINCT CASE WHEN ca.Score > 0 THEN 1 END) >= 1
ORDER BY 
    ca.TotalScore DESC, 
    ca.PostCount DESC,
    ca.GlobalPostRank ASC
LIMIT 1000;