-- {"query": "7502.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2286} 
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
        AVG(p.Score) as AvgPostScore,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        MAX(b.Date) as LastBadgeDate,
        STRING_AGG(DISTINCT p.PostTypeId::TEXT, ',') as PostTypeIds
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2010-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        PostCount,
        CommentCount,
        BadgeCount,
        AvgPostScore,
        LastPostDate,
        LastCommentDate,
        LastBadgeDate,
        PostTypeIds,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, PostCount DESC) as RankByReputation,
        DENSE_RANK() OVER (ORDER BY AVGPostScore DESC) as RankByAvgScore,
        NTILE(100) OVER (ORDER BY Views DESC) as PercentileByViews
    FROM UserActivityStats
    WHERE PostCount > 0
),
PostAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        LENGTH(p.Body) as BodyLength,
        COALESCE(p.AcceptedAnswerId, 0) as HasAcceptedAnswer,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN 'Question with Answers'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 1 AND p.AnswerCount IS NULL THEN 'Question without Answers'
            ELSE 'Other'
        END as PostCategory,
        CASE 
            WHEN p.Score > 100 THEN 'Highly Rated'
            WHEN p.Score > 50 THEN 'Moderately Rated'
            WHEN p.Score > 0 THEN 'Slightly Rated'
            ELSE 'No Rating'
        END as ScoreCategory,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) as ScoreRankWithinType,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as OwnerAvgScore,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PreviousScore,
        LEAD(p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as NextPostDate,
        NTH_VALUE(p.Score, 3) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as ThirdHighestScore,
        STRING_AGG(LEFT(p.Title, 20), ' | ') OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) as RecentTitles,
        CASE 
            WHEN EXISTS (SELECT 1 FROM Posts p2 WHERE p2.ParentId = p.Id AND p2.PostTypeId = 2 AND p2.Score > 0) 
            THEN 1 
            ELSE 0 
        END as HasHighScoringAnswers
    FROM Posts p
    WHERE p.CreationDate >= '2015-01-01'
    AND p.OwnerUserId IS NOT NULL
),
PostTagAnalysis AS (
    SELECT 
        pa.PostId,
        pa.Title,
        pa.Score,
        pa.PostTypeId,
        STRING_TO_ARRAY(REPLACE(REPLACE(pa.Tags, '<', ''), '>', ''), '<>') as TagArray,
        UNNEST(STRING_TO_ARRAY(REPLACE(REPLACE(pa.Tags, '<', ''), '>', ''), '<>')) as IndividualTag,
        COUNT(*) OVER (PARTITION BY pa.OwnerUserId) as UserPostCount,
        SUM(pa.Score) OVER (PARTITION BY pa.OwnerUserId) as UserTotalScore,
        CASE 
            WHEN pa.Score > 10 THEN 'Popular'
            WHEN pa.Score > 5 THEN 'Moderate'
            ELSE 'Low'
        END as PopularityLevel,
        ROW_NUMBER() OVER (PARTITION BY pa.OwnerUserId ORDER BY pa.Score DESC) as PostRankByScore,
        ROW_NUMBER() OVER (PARTITION BY pa.OwnerUserId ORDER BY pa.CreationDate DESC) as PostRankByDate
    FROM PostAnalysis pa
    WHERE pa.Tags IS NOT NULL 
    AND pa.Tags != ''
),
CombinedStats AS (
    SELECT 
        tu.UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.PostCount,
        tu.CommentCount,
        tu.BadgeCount,
        tu.AvgPostScore,
        CASE 
            WHEN COALESCE(tu.PostCount, 0) > 0 THEN (tu.CommentCount * 100.0) / NULLIF(tu.PostCount, 0)
            ELSE 0 
        END as CommentsPerPost,
        CASE 
            WHEN COALESCE(tu.BadgeCount, 0) > 0 THEN (tu.PostCount * 100.0) / NULLIF(tu.BadgeCount, 0)
            ELSE 0 
        END as PostsPerBadge,
        CASE 
            WHEN tu.RankByReputation <= 100 THEN 'Top 100'
            WHEN tu.RankByReputation <= 1000 THEN 'Top 1000'
            ELSE 'Below Top 1000'
        END as ReputationTier,
        CASE 
            WHEN tu.RankByAvgScore <= 50 THEN 'High Scoring'
            WHEN tu.RankByAvgScore <= 200 THEN 'Medium Scoring'
            ELSE 'Low Scoring'
        END as ScoringTier,
        tu.PercentileByViews,
        STRING_AGG(pTa.IndividualTag, ', ') as TagsUsed,
        STRING_AGG(pTa.PopularityLevel, ', ') as PopularityLevels,
        COUNT(DISTINCT pTa.IndividualTag) as UniqueTags,
        MAX(pTa.PostRankByScore) as MaxScoreRank,
        MIN(pTa.PostRankByDate) as MinDateRank,
        ARRAY_AGG(pTa.PostId) as PostIdsArray,
        COUNT(pTa.PostId) as TotalPostsAnalysis,
        SUM(CASE WHEN pTa.PopularityLevel = 'Popular' THEN 1 ELSE 0 END) as PopularPosts,
        SUM(CASE WHEN pTa.PopularityLevel = 'Moderate' THEN 1 ELSE 0 END) as ModeratePosts,
        SUM(CASE WHEN pTa.PopularityLevel = 'Low' THEN 1 ELSE 0 END) as LowPosts,
        AVG(CASE 
            WHEN pTa.PostRankByScore <= 5 THEN 100 
            WHEN pTa.PostRankByScore <= 10 THEN 75
            WHEN pTa.PostRankByScore <= 20 THEN 50
            ELSE 25 
        END) as RankingScore
    FROM TopUsers tu
    LEFT JOIN PostTagAnalysis pTa ON tu.UserId = (
        SELECT p.OwnerUserId FROM Posts p WHERE p.Id = pTa.PostId
    )
    GROUP BY tu.UserId, tu.DisplayName, tu.Reputation, tu.PostCount, 
             tu.CommentCount, tu.BadgeCount, tu.AvgPostScore, 
             tu.RankByReputation, tu.RankByAvgScore, tu.PercentileByViews
)
SELECT 
    c.UserId,
    c.DisplayName,
    c.Reputation,
    c.PostCount,
    c.CommentCount,
    c.BadgeCount,
    c.AvgPostScore,
    c.CommentsPerPost,
    c.PostsPerBadge,
    c.ReputationTier,
    c.ScoringTier,
    c.PercentileByViews,
    c.UniqueTags,
    c.MaxScoreRank,
    c.MinDateRank,
    c.TotalPostsAnalysis,
    c.PopularPosts,
    c.ModeratePosts,
    c.LowPosts,
    c.RankingScore,
    CASE 
        WHEN c.PostsPerBadge > 5 THEN 'Highly Active'
        WHEN c.PostsPerBadge > 2 THEN 'Moderately Active'
        WHEN c.PostsPerBadge > 0 THEN 'Low Activity'
        ELSE 'Inactive'
    END as ActivityLevel,
    CASE 
        WHEN c.RankingScore > 80 THEN 'High Performed'
        WHEN c.RankingScore > 60 THEN 'Medium Performed'
        WHEN c.RankingScore > 40 THEN 'Low Performed'
        ELSE 'Very Low Performed'
    END as PerformanceLevel,
    CASE 
        WHEN c.PercentileByViews > 90 THEN 'Very High Viewership'
        WHEN c.PercentileByViews > 75 THEN 'High Viewership'
        WHEN c.PercentileByViews > 50 THEN 'Medium Viewership'
        ELSE 'Low Viewership'
    END as ViewershipLevel,
    CASE 
        WHEN c.CommentsPerPost > 10 THEN 'Very Engaged'
        WHEN c.CommentsPerPost > 5 THEN 'Engaged'
        WHEN c.CommentsPerPost > 1 THEN 'Some Engagement'
        ELSE 'Minimal Engagement'
    END as EngagementLevel,
    CASE 
        WHEN c.TotalPostsAnalysis > 500 THEN 'High Volume'
        WHEN c.TotalPostsAnalysis > 100 THEN 'Medium Volume'
        WHEN c.TotalPostsAnalysis > 10 THEN 'Low Volume'
        ELSE 'Very Low Volume'
    END as VolumeLevel,
    COALESCE(c.TagsUsed, 'No Tags') as TagSummary,
    COALESCE(c.PopularityLevels, 'No Data') as PopularitySummary
FROM CombinedStats c
WHERE 
    c.Reputation > 1000 
    AND c.PostCount > 10 
    AND (c.CommentsPerPost > 0 OR c.PostsPerBadge > 0)
    AND c.UniqueTags > 0
    AND c.RankingScore IS NOT NULL
ORDER BY 
    c.Reputation DESC, 
    c.AvgPostScore DESC,
    c.TotalPostsAnalysis DESC,
    c.PopularPosts DESC
LIMIT 2000;