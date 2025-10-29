-- {"query": "7779.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2412} 
WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        MAX(p.CreationDate) as LastPostDate,
        AVG(p.Score) as AvgPostScore,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') as AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.AccountId
),
PostAnalysis AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Tags,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'Question with Accepted Answer'
            WHEN p.PostTypeId = 1 THEN 'Question without Answer'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostTypeDescription,
        COALESCE(p.AnswerCount, 0) + COALESCE(p.CommentCount, 0) as EngagementCount,
        DATEDIFF(day, p.CreationDate, CURRENT_TIMESTAMP) as AgeInDays,
        NTILE(10) OVER (ORDER BY p.Score DESC) as ScoreDecile,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as UserPostRank,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevScore,
        CASE 
            WHEN p.Score > LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) THEN 1
            WHEN p.Score < LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) THEN -1
            ELSE 0
        END as ScoreChangeTrend,
        CASE 
            WHEN p.ViewCount > 1000 THEN 'High Viewed'
            WHEN p.ViewCount > 100 THEN 'Medium Viewed'
            ELSE 'Low Viewed'
        END as ViewCategory,
        TRIM(BOTH '<>' FROM COALESCE(p.Tags, '')) as CleanTags,
        (SELECT COUNT(*) FROM Posts WHERE ParentId = p.Id AND PostTypeId = 2) as AnswerCountIncludingDeleted
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular Tag'
            WHEN t.Count > 100 THEN 'Moderate Tag'
            ELSE 'Rare Tag'
        END as TagPopularity,
        RANK() OVER (ORDER BY t.Count DESC) as TagRank,
        LAG(t.Count) OVER (ORDER BY t.Count DESC) as PrevCount,
        t.Count - LAG(t.Count) OVER (ORDER BY t.Count DESC) as CountDifference
    FROM Tags t
    WHERE t.Count > 0
),
AdvancedUserAnalysis AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        (u.UpVotes - u.DownVotes) as NetVotes,
        CASE 
            WHEN u.Reputation > 100000 THEN 'Expert'
            WHEN u.Reputation > 10000 THEN 'Advanced'
            WHEN u.Reputation > 1000 THEN 'Intermediate'
            ELSE 'Beginner'
        END as RepLevel,
        (SELECT COUNT(*) FROM Badges WHERE UserId = u.Id AND Class = 1) as GoldBadges,
        (SELECT COUNT(*) FROM Badges WHERE UserId = u.Id AND Class = 2) as SilverBadges,
        (SELECT COUNT(*) FROM Badges WHERE UserId = u.Id AND Class = 3) as BronzeBadges,
        (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = u.Id AND PostTypeId = 1) as QuestionCount,
        (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = u.Id AND PostTypeId = 2) as AnswerCount
    FROM Users u
    WHERE u.Reputation BETWEEN 1000 AND 1000000
),
FinalAggregation AS (
    SELECT 
        'Post Statistics' as AnalysisType,
        COUNT(*) as TotalRecords,
        COUNT(DISTINCT pa.OwnerUserId) as UniqueAuthors,
        AVG(pa.Score) as AvgScore,
        MAX(pa.Score) as MaxScore,
        MIN(pa.Score) as MinScore,
        COUNT(CASE WHEN pa.Score > 0 THEN 1 END) as PositiveScoreCount,
        COUNT(CASE WHEN pa.Score < 0 THEN 1 END) as NegativeScoreCount,
        SUM(pa.ViewCount) as TotalViews,
        AVG(pa.AnswerCountIncludingDeleted) as AvgAnswerCount,
        AVG(pa.An EngagementCount) as AvgEngagement,
        NULL as CommentData,
        NULL as BadgeData,
        NULL as TagData
    FROM PostAnalysis pa
    
    UNION ALL
    
    SELECT 
        'User Statistics' as AnalysisType,
        COUNT(*) as TotalRecords,
        COUNT(DISTINCT usa.Id) as UniqueUsers,
        AVG(usa.Reputation) as AvgReputation,
        MAX(usa.Reputation) as MaxReputation,
        MIN(usa.Reputation) as MinReputation,
        COUNT(CASE WHEN usa.Reputation > 10000 THEN 1 END) as HighReputationUsers,
        COUNT(CASE WHEN usa.Reputation < 1000 THEN 1 END) as LowReputationUsers,
        SUM(usa.UpVotes) as TotalUpVotes,
        SUM(usa.DownVotes) as TotalDownVotes,
        AVG(usa.NetVotes) as AvgNetVotes,
        SUM(usa.GoldBadges) as TotalGoldBadges,
        NULL as CommentData,
        NULL as BadgeData,
        NULL as TagData
    FROM AdvancedUserAnalysis usa
    
    UNION ALL
    
    SELECT 
        'Tag Statistics' as AnalysisType,
        COUNT(*) as TotalRecords,
        NULL as UniqueUsers,
        AVG(ta.Count) as AvgTagCount,
        MAX(ta.Count) as MaxTagCount,
        MIN(ta.Count) as MinTagCount,
        NULL as PositiveScoreCount,
        NULL as NegativeScoreCount,
        NULL as TotalViews,
        NULL as AvgAnswerCount,
        NULL as AvgEngagement,
        NULL as CommentData,
        NULL as BadgeData,
        NULL as TagData
    FROM TagAnalysis ta
)
SELECT 
    fa.AnalysisType,
    fa.TotalRecords,
    fa.UniqueAuthors as UniqueAuthorsOrUsers,
    fa.AvgScore as AvgScoreOrReputation,
    fa.MaxScore as MaxScoreOrReputation,
    fa.MinScore as MinScoreOrReputation,
    fa.PositiveScoreCount as HighReputationUsersOrPositiveScores,
    fa.NegativeScoreCount as LowReputationUsersOrNegativeScores,
    fa.TotalViews as TotalViewsOrUpVotes,
    fa.AvgAnswerCount as AvgAnswerCountOrDownVotes,
    fa.AvgEngagement as AvgEngagementOrNetVotes,
    CASE 
        WHEN fa.AnalysisType = 'Post Statistics' THEN (
            SELECT STRING_AGG(CONCAT('Tag: ', ta.TagName, ' Count: ', ta.Count), '; ')
            FROM TagAnalysis ta
            WHERE RANK() OVER (ORDER BY ta.Count DESC) <= 5
        )
        WHEN fa.AnalysisType = 'User Statistics' THEN (
            SELECT STRING_AGG(CONCAT('User: ', usa.DisplayName, ' Rep: ', usa.Reputation), '; ')
            FROM AdvancedUserAnalysis usa
            WHERE RANK() OVER (ORDER BY usa.Reputation DESC) <= 5
        )
        ELSE (
            SELECT STRING_AGG(CONCAT('Post: ', pa.Title, ' Score: ', pa.Score), '; ')
            FROM PostAnalysis pa
            WHERE RANK() OVER (ORDER BY pa.Score DESC) <= 5
        )
    END as TopItems,
    CASE 
        WHEN fa.AnalysisType = 'Post Statistics' THEN (
            SELECT COUNT(*) 
            FROM Posts p 
            WHERE p.OwnerUserId IN (SELECT Id FROM Users WHERE Reputation > 100000)
        )
        WHEN fa.AnalysisType = 'User Statistics' THEN (
            SELECT COUNT(*) 
            FROM Users u 
            WHERE u.Id IN (SELECT UserId FROM Badges WHERE Class = 1)
        )
        ELSE (
            SELECT COUNT(*) 
            FROM Tags t 
            WHERE t.Count > 1000
        )
    END as SpecialCount,
    COALESCE(
        (SELECT COUNT(*) FROM UserStats us WHERE us.Reputation > 10000),
        (SELECT COUNT(*) FROM Posts p WHERE p.Score > 1000),
        (SELECT COUNT(*) FROM Tags t WHERE t.Count > 1000)
    ) as ConditionalCount,
    (SELECT COUNT(*) FROM Votes v JOIN Posts p ON v.PostId = p.Id WHERE v.VoteTypeId = 2 AND p.Score > 100) as HighScoreUpvotes,
    RANK() OVER (ORDER BY fa.TotalRecords DESC) as CategoryRank,
    ROW_NUMBER() OVER (ORDER BY fa.AvgScore DESC) as ScoreRank,
    NTILE(4) OVER (ORDER BY fa.UniqueAuthors) as UserPopulationQuartile,
    CASE 
        WHEN fa.TotalRecords > (SELECT AVG(TotalRecords) FROM FinalAggregation) THEN 'Above Average'
        ELSE 'Below Average'
    END as PerformanceCategory,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId IN (SELECT Id FROM Posts WHERE Score > 100)) as HighScorePostHistoryCount,
    CASE 
        WHEN fa.AnalysisType = 'Post Statistics' THEN (
            SELECT STRING_AGG(pa.Title, ', ') 
            FROM PostAnalysis pa 
            WHERE pa.Score > (SELECT AVG(Score) FROM PostAnalysis) AND pa.AgeInDays > 30
        )
        ELSE NULL
    END as QualifiedPosts,
    (SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId = 1 AND p.AnswerCount > 0) as QuestionWithAnswers,
    (SELECT AVG(AnswerCountIncludingDeleted) FROM PostAnalysis) as OverallAvgAnswerDepth,
    (SELECT COUNT(*) FROM Posts p WHERE p.Score > (SELECT AVG(Score) FROM Posts)) as AboveAverageScorePosts,
    (SELECT COUNT(*) FROM Posts p WHERE p.ViewCount > (SELECT AVG(ViewCount) FROM Posts)) as AboveAverageViewPosts
FROM FinalAggregation fa
WHERE fa.AnalysisType IN ('Post Statistics', 'User Statistics', 'Tag Statistics')
    AND fa.TotalRecords > 0
ORDER BY fa.AnalysisType, fa.TotalRecords DESC, fa.AvgScore DESC;