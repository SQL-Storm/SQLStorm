-- {"query": "7326.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2208} 
WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.CreationDate,
        u.DisplayName,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) as QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) as AnswerCount,
        MAX(p.Score) as MaxPostScore,
        AVG(p.Score) as AvgPostScore,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') as AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.Reputation, u.CreationDate, u.DisplayName
),
TopUsers AS (
    SELECT 
        UserId,
        Reputation,
        PostCount,
        CommentCount,
        BadgeCount,
        QuestionCount,
        AnswerCount,
        MaxPostScore,
        AvgPostScore,
        AllTags,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, PostCount DESC) as RowNum
    FROM UserStats
),
RecentActivity AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        u.DisplayName as OwnerName,
        CASE WHEN u.Id IS NULL THEN 'Deleted User' ELSE u.DisplayName END as OwnerDisplayName,
        COALESCE(p.AnswerCount, 0) + COALESCE(p.CommentCount, 0) as EngagementCount,
        DATEDIFF(day, p.CreationDate, CURRENT_TIMESTAMP) as DaysOld,
        CASE 
            WHEN p.Score > 100 THEN 'Gold'
            WHEN p.Score > 50 THEN 'Silver'
            WHEN p.Score > 10 THEN 'Bronze'
            ELSE 'Common'
        END as ScoreTier,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostType,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PreviousScore,
        ROUND(AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2) as MovingAvgScore,
        RANK() OVER (ORDER BY p.Score DESC) as ScoreRank
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.CreationDate >= DATEADD(day, -30, CURRENT_TIMESTAMP)
      AND p.PostTypeId IN (1, 2)
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Trending'
            WHEN t.Count > 500 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            ELSE 'Niche'
        END as PopularityLevel,
        RANK() OVER (ORDER BY t.Count DESC) as TagRank,
        DENSE_RANK() OVER (ORDER BY t.Count DESC) as TagDenseRank
    FROM Tags t
    WHERE t.Count > 50
),
ComplexVotes AS (
    SELECT 
        v.PostId,
        v.VoteTypeId,
        v.UserId,
        v.CreationDate,
        v.BountyAmount,
        CASE 
            WHEN v.VoteTypeId IN (8, 9) AND v.BountyAmount > 100 THEN 'HighBounty'
            WHEN v.VoteTypeId IN (8, 9) AND v.BountyAmount > 50 THEN 'MidBounty'
            WHEN v.VoteTypeId IN (8, 9) THEN 'LowBounty'
            ELSE 'OtherVote'
        END as BountyCategory,
        DATEDIFF(day, v.CreationDate, CURRENT_TIMESTAMP) as DaysSinceVote,
        COUNT(*) OVER (PARTITION BY v.PostId) as VoteCountPerPost
    FROM Votes v
    WHERE v.VoteTypeId IN (1, 2, 3, 8, 9)
        AND v.CreationDate >= DATEADD(day, -90, CURRENT_TIMESTAMP)
),
UserEngagement AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(us.PostCount, 0) as TotalPosts,
        COALESCE(us.CommentCount, 0) as TotalComments,
        COALESCE(us.BadgeCount, 0) as TotalBadges,
        CASE 
            WHEN us.PostCount IS NULL OR us.PostCount = 0 THEN 0
            ELSE (COALESCE(us.CommentCount, 0) * 100.0 / us.PostCount)
        END as CommentToPostRatio,
        CASE 
            WHEN us.PostCount IS NULL OR us.PostCount = 0 THEN 0
            ELSE (COALESCE(us.BadgeCount, 0) * 100.0 / us.PostCount)
        END as BadgeToPostRatio,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, us.PostCount DESC) as EngagementRank
    FROM Users u
    LEFT JOIN UserStats us ON u.Id = us.UserId
    WHERE u.Reputation > 500
),
CombinedStats AS (
    SELECT 
        ra.PostId,
        ra.Title,
        ra.Score,
        ra.ViewCount,
        ra.OwnerUserId,
        ra.OwnerDisplayName,
        ra.TagRank,
        ra.ScoreTier,
        ra.EngagementCount,
        ra.DaysOld,
        ra.PostType,
        ra.ScoreRank,
        ta.TagName,
        ta.PopularityLevel,
        cv.BountyCategory,
        cv.VoteCountPerPost,
        ue.CommentToPostRatio,
        ue.BadgeToPostRatio,
        ue.EngagementRank,
        CASE 
            WHEN ra.Score > 0 AND ra.ViewCount > 0 THEN 
                ROUND((ra.Score * 100.0 / ra.ViewCount), 2)
            ELSE 0
        END as QualityScore
    FROM RecentActivity ra
    LEFT JOIN Tags ta ON ta.TagName = ANY (STRING_TO_ARRAY(SUBSTRING(ra.Tags, 2, LENGTH(ra.Tags)-2), '><'))
    LEFT JOIN ComplexVotes cv ON ra.PostId = cv.PostId
    LEFT JOIN UserEngagement ue ON ra.OwnerUserId = ue.UserId
    WHERE ra.PostId IS NOT NULL
),
FinalAggregation AS (
    SELECT 
        'Posts Analysis' as AnalysisType,
        COUNT(*) as RecordCount,
        COUNT(DISTINCT OwnerUserId) as UniqueUsers,
        SUM(QualityScore) as TotalQualityScore,
        AVG(QualityScore) as AvgQualityScore,
        MAX(QualityScore) as MaxQualityScore,
        MIN(QualityScore) as MinQualityScore,
        STRING_AGG(DISTINCT ScoreTier, ', ') as ScoreTiers,
        STRING_AGG(DISTINCT PopularityLevel, ', ') as PopularityLevels
    FROM CombinedStats
    WHERE ScoreTier IS NOT NULL
    
    UNION ALL
    
    SELECT 
        'User Engagement Analysis' as AnalysisType,
        COUNT(*) as RecordCount,
        COUNT(DISTINCT OwnerUserId) as UniqueUsers,
        SUM(QualityScore) as TotalQualityScore,
        AVG(QualityScore) as AvgQualityScore,
        MAX(QualityScore) as MaxQualityScore,
        MIN(QualityScore) as MinQualityScore,
        STRING_AGG(DISTINCT ScoreTier, ', ') as ScoreTiers,
        STRING_AGG(DISTINCT PopularityLevel, ', ') as PopularityLevels
    FROM CombinedStats
    WHERE EngagementRank <= 50
    
    UNION ALL
    
    SELECT 
        'Tag Popularity Analysis' as AnalysisType,
        COUNT(*) as RecordCount,
        COUNT(DISTINCT OwnerUserId) as UniqueUsers,
        SUM(QualityScore) as TotalQualityScore,
        AVG(QualityScore) as AvgQualityScore,
        MAX(QualityScore) as MaxQualityScore,
        MIN(QualityScore) as MinQualityScore,
        STRING_AGG(DISTINCT ScoreTier, ', ') as ScoreTiers,
        STRING_AGG(DISTINCT PopularityLevel, ', ') as PopularityLevels
    FROM CombinedStats
    WHERE TagName IS NOT NULL
)
SELECT 
    fa.AnalysisType,
    fa.RecordCount,
    fa.UniqueUsers,
    fa.TotalQualityScore,
    fa.AvgQualityScore,
    fa.MaxQualityScore,
    fa.MinQualityScore,
    fa.ScoreTiers,
    fa.PopularityLevels,
    COUNT(*) OVER (ORDER BY fa.AnalysisType) as SortOrder,
    STRING_AGG(CONCAT('Top User: ', OwnerDisplayName, ' (Score: ', MAX(Score), ')'), '; ') 
        FILTER (WHERE CASE WHEN fa.AnalysisType = 'Posts Analysis' THEN 1 ELSE 0 END) as TopUsersByScore,
    STRING_AGG(CONCAT('Tag: ', TagName, ' (Count: ', COUNT(*), ')'), '; ') 
        FILTER (WHERE CASE WHEN fa.AnalysisType = 'Tag Popularity Analysis' THEN 1 ELSE 0 END) as PopularTags,
    STRING_AGG(CONCAT('User: ', DisplayName, ' (Reputation: ', MAX(Reputation), ')'), '; ') 
        FILTER (WHERE CASE WHEN fa.AnalysisType = 'User Engagement Analysis' THEN 1 ELSE 0 END) as TopEngagedUsers
FROM FinalAggregation fa
JOIN Users u ON u.Id = (SELECT OwnerUserId FROM CombinedStats WHERE QualityScore = (SELECT MAX(QualityScore) FROM CombinedStats))
JOIN CombinedStats cs ON cs.OwnerUserId = u.Id
GROUP BY 
    fa.AnalysisType,
    fa.RecordCount,
    fa.UniqueUsers,
    fa.TotalQualityScore,
    fa.AvgQualityScore,
    fa.MaxQualityScore,
    fa.MinQualityScore,
    fa.ScoreTiers,
    fa.PopularityLevels
ORDER BY SortOrder;