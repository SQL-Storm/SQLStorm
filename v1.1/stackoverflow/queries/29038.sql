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
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        COALESCE(SUM(p.ViewCount), 0) as TotalViews,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC, u.Reputation DESC) as UserRank,
        CASE WHEN COUNT(p.Id) = 0 THEN NULL ELSE SUM(p.Score) * 1.0 / COUNT(p.Id) END as AvgPostScore,
        PERCENT_RANK() OVER (ORDER BY u.Reputation DESC) as ReputationPercentile
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        COALESCE(SUM(p.Score), 0) as RelatedPostScore,
        COUNT(DISTINCT p.Id) as RelatedPostCount,
        STRING_AGG(DISTINCT CAST(p.OwnerUserId AS VARCHAR), ', ') as TagContributors,
        CASE 
            WHEN t.Count > 100 THEN 'Popular'
            WHEN t.Count > 50 THEN 'Moderate'
            WHEN t.Count > 10 THEN 'Niche'
            ELSE 'Rare'
        END as TagPopularity,
        NTILE(4) OVER (ORDER BY t.Count DESC) as Quartile
    FROM Tags t
    LEFT JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE t.TagName IS NOT NULL
    GROUP BY t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId
),
ComplexPostAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Body,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.ParentId,
        p.AnswerCount,
        p.CommentCount,
        p.Tags,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END as PostTypeDesc,
        CASE 
            WHEN p.Score > 100 THEN 'Highly Voted'
            WHEN p.Score > 50 THEN 'Moderately Voted'
            WHEN p.Score > 0 THEN 'Low Voted'
            ELSE 'No Votes'
        END as VoteClassification,
        (p.Tags IS NOT NULL AND p.Tags <> '') as HasTags,
        (p.Tags IS NOT NULL AND p.Tags SIMILAR TO '%<[^>]+>%|<[^>]+>%') as HasWellFormedTags,
        LENGTH(p.Body) as BodyLength,
        LENGTH(p.Title) as TitleLength,
        EXTRACT(DAY FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - p.CreationDate)) as AgeInDays,
        CASE 
            WHEN EXTRACT(DAY FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - p.CreationDate)) > 365 THEN 'Old'
            WHEN EXTRACT(DAY FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - p.CreationDate)) > 30 THEN 'Recent'
            ELSE 'Very Recent'
        END as PostAgeCategory,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevScore,
        p.Score - LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as ScoreChange,
        FIRST_VALUE(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as UserFirstScore,
        LAST_VALUE(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as UserLastScore,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as UserAverageScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as UserPostSequence,
        NTH_VALUE(p.Score, 3) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as ThirdPostScore,
        -- Replace unsupported STRING_AGG as window function: compute recent 3 tags via correlated subquery aggregation
        (SELECT STRING_AGG(pt.Tags, '; ')
         FROM (
             SELECT p2.Tags
             FROM Posts p2
             WHERE p2.OwnerUserId = p.OwnerUserId
               AND p2.CreationDate <= p.CreationDate
             ORDER BY p2.CreationDate DESC
             LIMIT 3
         ) pt
        ) as RecentTags3,
        CASE 
            WHEN p.Score > 50 AND p.ViewCount > 1000 THEN 'High Impact'
            WHEN p.Score > 20 AND p.ViewCount > 500 THEN 'Medium Impact'
            WHEN p.Score > 5 AND p.ViewCount > 100 THEN 'Low Impact'
            ELSE 'Minimal Impact'
        END as ImpactLevel,
        CASE 
            WHEN p.CommentCount > 10 THEN 'Highly Commented'
            WHEN p.CommentCount > 5 THEN 'Moderately Commented'
            WHEN p.CommentCount > 0 THEN 'Sparingly Commented'
            ELSE 'No Comments'
        END as CommentActivityLevel
    FROM Posts p
    WHERE p.Id IS NOT NULL
),
CombinedAnalysis AS (
    SELECT 
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.PostCount,
        uas.QuestionCount,
        uas.AnswerCount,
        uas.TotalScore,
        uas.TotalViews,
        uas.UserRank,
        uas.ReputationPercentile,
        ta.TagName,
        ta.TagCount,
        ta.RelatedPostScore,
        ta.RelatedPostCount,
        ta.TagPopularity,
        ta.Quartile,
        cpa.PostId,
        cpa.Title,
        cpa.Score,
        cpa.ViewCount,
        cpa.CreationDate,
        cpa.PostTypeDesc,
        cpa.VoteClassification,
        cpa.PostAgeCategory,
        cpa.AgeInDays,
        cpa.ScoreChange,
        cpa.UserAverageScore,
        cpa.ImpactLevel,
        cpa.CommentActivityLevel,
        (CASE WHEN uas.QuestionCount > 0 THEN (uas.QuestionCount * 10) ELSE 0 END +
         CASE WHEN uas.AnswerCount > 0 THEN (uas.AnswerCount * 5) ELSE 0 END +
         CASE WHEN uas.PostCount > 0 THEN (uas.PostCount * 2) ELSE 0 END +
         CASE WHEN uas.TotalScore > 0 THEN ROUND(uas.TotalScore / 10.0) ELSE 0 END +
         CASE WHEN cpa.Score > 0 THEN ROUND(cpa.Score / 10.0) ELSE 0 END +
         (CASE WHEN ta.RelatedPostCount > 0 THEN (ta.RelatedPostCount * 3) ELSE 0 END)) as EngagementScore,
        CASE 
            WHEN ta.TagPopularity = 'Popular' THEN 100
            WHEN ta.TagPopularity = 'Moderate' THEN 75
            WHEN ta.TagPopularity = 'Niche' THEN 50
            WHEN ta.TagPopularity = 'Rare' THEN 25
            ELSE 0
        END +
        CASE 
            WHEN ta.RelatedPostCount > 100 THEN 50
            WHEN ta.RelatedPostCount > 50 THEN 30
            WHEN ta.RelatedPostCount > 10 THEN 15
            ELSE 5
        END as TagPopularityIndex,
        (cpa.Score * 1.0 / (1 + (cpa.AgeInDays / 30.0))) as RiskAdjustedScore,
        CASE 
            WHEN cpa.ImpactLevel = 'High Impact' THEN (cpa.Score * cpa.ViewCount * 0.001)
            WHEN cpa.ImpactLevel = 'Medium Impact' THEN (cpa.Score * cpa.ViewCount * 0.0005)
            WHEN cpa.ImpactLevel = 'Low Impact' THEN (cpa.Score * cpa.ViewCount * 0.0001)
            ELSE (cpa.Score * cpa.ViewCount * 0.00001)
        END as WeightedImpactScore
    FROM UserActivityStats uas
    FULL OUTER JOIN TagAnalysis ta ON TRUE
    JOIN ComplexPostAnalysis cpa ON (
        (uas.UserId IS NOT NULL AND cpa.OwnerUserId = uas.UserId) OR 
        (ta.TagName IS NOT NULL AND cpa.Tags LIKE '%' || ta.TagName || '%')
    )
    WHERE (uas.UserId IS NOT NULL OR ta.TagName IS NOT NULL OR cpa.PostId IS NOT NULL)
)
SELECT 
    COUNT(*) as TotalRecords,
    COUNT(DISTINCT UserId) as UniqueUsers,
    COUNT(DISTINCT TagName) as UniqueTags,
    COUNT(DISTINCT PostId) as UniquePosts,
    AVG(EngagementScore) as AvgEngagementScore,
    AVG(TagPopularityIndex) as AvgTagPopularityIndex,
    AVG(RiskAdjustedScore) as AvgRiskAdjustedScore,
    AVG(WeightedImpactScore) as AvgWeightedImpactScore,
    MAX(Reputation) as MaxReputation,
    MIN(Reputation) as MinReputation,
    SUM(TotalScore) as TotalScoreAcrossAllPosts,
    SUM(TotalViews) as TotalViewsAcrossAllPosts,
    COUNT(CASE WHEN TagPopularity = 'Popular' THEN 1 END) as PopularTagsCount,
    COUNT(CASE WHEN ImpactLevel = 'High Impact' THEN 1 END) as HighImpactPostsCount
FROM CombinedAnalysis
WHERE 
    (UserId IS NOT NULL OR TagName IS NOT NULL OR PostId IS NOT NULL)
    AND EngagementScore > 0 
    AND RiskAdjustedScore > 0
    AND (TagName IS NULL OR TagName <> '')
    AND (PostId IS NOT NULL OR UserId IS NOT NULL)
GROUP BY 
    UserId, TagName, PostId, EngagementScore, TagPopularityIndex, RiskAdjustedScore, WeightedImpactScore, Reputation, TotalScore, TotalViews, TagPopularity, ImpactLevel
HAVING 
    COUNT(*) > 0
    AND COUNT(DISTINCT UserId) > 0
    AND COUNT(DISTINCT TagName) > 0
    AND COUNT(DISTINCT PostId) > 0
ORDER BY 
    AVG(EngagementScore) DESC,
    AVG(TagPopularityIndex) DESC,
    AVG(RiskAdjustedScore) DESC
LIMIT 1000;