-- {"query": "7344.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3712} 
WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        SUM(COALESCE(p.Score, 0)) as TotalScore,
        AVG(COALESCE(p.Score, 0)) as AvgScore,
        MAX(p.CreationDate) as LastPostDate,
        COUNT(DISTINCT b.Id) as BadgeCount,
        STRING_AGG(DISTINCT b.Name, ', ') as BadgesEarned,
        RANK() OVER (ORDER BY SUM(COALESCE(p.Score, 0)) DESC) as ScoreRank,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as PostRank,
        NTILE(100) OVER (ORDER BY u.Reputation DESC) as ReputationPercentile,
        CASE 
            WHEN COUNT(DISTINCT p.Id) = 0 THEN NULL 
            ELSE EXTRACT(YEAR FROM AGE(MAX(p.CreationDate), MIN(p.CreationDate))) 
        END as YearsActive
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
PostActivity AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.LastActivityDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.Tags,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostType,
        COALESCE(p.OwnerDisplayName, 'Anonymous') as OwnerDisplayName,
        COALESCE(u.DisplayName, 'Unknown') as OwnerName,
        COALESCE(p.Score, 0) - COALESCE(LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate), 0) as ScoreChange,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as RecentPostRank,
        CASE 
            WHEN p.Score > 1000 THEN 'Viral'
            WHEN p.Score > 500 THEN 'Popular'
            WHEN p.Score > 100 THEN 'Notable'
            ELSE 'Regular'
        END as PopularityLevel,
        LAG(p.Score) OVER (ORDER BY p.CreationDate) as PrevScore,
        LEAD(p.Score) OVER (ORDER BY p.CreationDate) as NextScore,
        -- Complex tag analysis
        CASE 
            WHEN p.Tags IS NOT NULL AND LENGTH(p.Tags) > 0 THEN
                (SELECT COUNT(*) FROM unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) t(tag))
            ELSE 0 
        END as TagCount,
        -- Calculate time since last activity
        CASE 
            WHEN p.LastActivityDate IS NOT NULL THEN EXTRACT(DAY FROM AGE(NOW(), p.LastActivityDate))
            ELSE NULL 
        END as DaysSinceLastActivity,
        -- Determine if post is trending
        CASE 
            WHEN p.Score > (SELECT AVG(Score) + STDDEV(Score) FROM Posts WHERE PostTypeId = 1 AND Score IS NOT NULL)
            AND EXTRACT(DAY FROM AGE(NOW(), p.CreationDate)) <= 30 THEN 1
            ELSE 0 
        END as IsTrending
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2)
),
CombinedActivity AS (
    SELECT 
        pa.PostId,
        pa.Title,
        pa.Score,
        pa.ViewCount,
        pa.AnswerCount,
        pa.CommentCount,
        pa.CreationDate,
        pa.LastActivityDate,
        pa.OwnerUserId,
        pa.PostTypeId,
        pa.Tags,
        pa.PostType,
        pa.OwnerDisplayName,
        pa.OwnerName,
        pa.ScoreChange,
        pa.RecentPostRank,
        pa.PopularityLevel,
        pa.PrevScore,
        pa.NextScore,
        pa.TagCount,
        pa.DaysSinceLastActivity,
        pa.IsTrending,
        us.DisplayName as UserDisplayName,
        us.Reputation,
        us.Views as UserViews,
        us.PostCount,
        us.QuestionCount,
        us.AnswerCount,
        us.TotalScore,
        us.AvgScore,
        us.BadgeCount,
        us.BadgesEarned,
        us.ScoreRank,
        us.PostRank,
        us.ReputationPercentile,
        us.YearsActive,
        -- Multi-criteria filtering and calculations
        CASE 
            WHEN pa.Score >= 100 AND pa.ViewCount > 1000 
            AND pa.AnswerCount >= 5 AND pa.CommentCount >= 10 
            THEN 'HighQuality'
            WHEN pa.Score >= 50 AND pa.ViewCount > 500 
            AND pa.AnswerCount >= 2 THEN 'Quality'
            WHEN pa.Score >= 25 AND pa.ViewCount > 100 THEN 'Decent' 
            ELSE 'Low'
        END as QualityLevel,
        -- Tag analysis - extract first tag for categorization
        CASE 
            WHEN pa.Tags IS NOT NULL AND LENGTH(pa.Tags) > 0 THEN
                (SELECT tag FROM unnest(string_to_array(substring(pa.Tags, 2, length(pa.Tags)-2), '><')) t(tag) LIMIT 1)
            ELSE 'NoTag'
        END as PrimaryTag,
        -- User engagement score - combining various metrics
        (COALESCE(pa.ViewCount, 0) * 0.1 + 
         COALESCE(pa.AnswerCount, 0) * 5 + 
         COALESCE(pa.CommentCount, 0) * 2 + 
         COALESCE(pa.Score, 0) * 0.5) as EngagementScore,
        -- Relative performance metrics
        COALESCE(pa.Score, 0) - 
        (SELECT AVG(Score) FROM Posts WHERE PostTypeId = pa.PostTypeId AND Score IS NOT NULL) as ScoreVsAvg,
        -- Time-based scoring factors
        CASE 
            WHEN EXTRACT(YEAR FROM AGE(NOW(), pa.CreationDate)) = 0 THEN 
                COALESCE(pa.Score, 0) * 1.5
            WHEN EXTRACT(YEAR FROM AGE(NOW(), pa.CreationDate)) BETWEEN 1 AND 2 THEN 
                COALESCE(pa.Score, 0) * 1.2
            ELSE 
                COALESCE(pa.Score, 0)
        END as AdjustedScore
    FROM PostActivity pa
    LEFT JOIN UserStats us ON pa.OwnerUserId = us.UserId
    WHERE pa.Score IS NOT NULL
),
FinalAnalysis AS (
    SELECT 
        ca.PostId,
        ca.Title,
        ca.Score,
        ca.ViewCount,
        ca.AnswerCount,
        ca.CommentCount,
        ca.CreationDate,
        ca.LastActivityDate,
        ca.OwnerUserId,
        ca.PostTypeId,
        ca.Tags,
        ca.PostType,
        ca.OwnerDisplayName,
        ca.OwnerName,
        ca.ScoreChange,
        ca.RecentPostRank,
        ca.PopularityLevel,
        ca.PrevScore,
        ca.NextScore,
        ca.TagCount,
        ca.DaysSinceLastActivity,
        ca.IsTrending,
        ca.UserDisplayName,
        ca.Reputation,
        ca.Views as UserViews,
        ca.PostCount,
        ca.QuestionCount,
        ca.AnswerCount as UserAnswerCount,
        ca.TotalScore as UserTotalScore,
        ca.AvgScore as UserAvgScore,
        ca.BadgeCount,
        ca.BadgesEarned,
        ca.ScoreRank,
        ca.PostRank,
        ca.ReputationPercentile,
        ca.YearsActive,
        ca.QualityLevel,
        ca.PrimaryTag,
        ca.EngagementScore,
        ca.ScoreVsAvg,
        ca.AdjustedScore,
        -- Advanced filtering with NULL handling
        COALESCE(ca.PrimaryTag, 'Unknown') as FinalTag,
        CASE 
            WHEN ca.Reputation > 10000 AND ca.UserTotalScore > 500 THEN 'Elite'
            WHEN ca.Reputation > 5000 AND ca.UserTotalScore > 200 THEN 'Veteran' 
            WHEN ca.Reputation > 1000 THEN 'Experienced'
            ELSE 'Beginner'
        END as UserStatus,
        -- Complex string operations and calculations
        CONCAT(
            'Post: ', 
            CASE 
                WHEN LENGTH(ca.Title) > 50 THEN LEFT(ca.Title, 47) || '...'
                ELSE ca.Title 
            END,
            ' (Score: ', ca.Score, ') by ', 
            COALESCE(ca.OwnerName, 'Anonymous')
        ) as PostSummary,
        -- Time series analysis using window functions
        ROW_NUMBER() OVER (ORDER BY ca.AdjustedScore DESC) as RankByAdjustedScore,
        AVG(ca.Score) OVER (ORDER BY ca.CreationDate ROWS BETWEEN 30 PRECEDING AND CURRENT ROW) as MovingAvgScore,
        -- Correlated subquery with complex conditions
        (SELECT COUNT(*) FROM Posts p2 
         WHERE p2.OwnerUserId = ca.OwnerUserId 
         AND p2.CreationDate > ca.CreationDate 
         AND p2.Score > ca.Score
        ) as BetterPostsCount,
        -- Set operations: finding posts that meet specific criteria
        CASE 
            WHEN ca.IsTrending = 1 AND ca.TagCount > 2 THEN 'TrendingAndTagged'
            WHEN ca.IsTrending = 1 THEN 'Trending'
            WHEN ca.TagCount > 2 THEN 'Tagged'
            ELSE 'Regular'
        END as PostCategory,
        -- NULL-safe complex calculations
        COALESCE(ca.Score, 0) * 
        COALESCE(CASE WHEN ca.ViewCount IS NULL THEN 1.0 ELSE (ca.ViewCount::float / (SELECT AVG(ViewCount) FROM Posts)) END, 1.0) as NormalizedScore,
        -- Calculated metrics using multiple joins and aggregations
        COALESCE(
            (SELECT COUNT(DISTINCT pv.PostId) 
             FROM Votes pv 
             WHERE pv.PostId = ca.PostId 
             AND pv.VoteTypeId IN (2, 3)), 0
        ) as VoteCount,
        -- Filtering based on calculated criteria
        CASE 
            WHEN ca.ScoreVsAvg > 0 AND ca.EngagementScore > 1000 THEN 1
            ELSE 0
        END as HighPerformanceIndicator
    FROM CombinedActivity ca
    WHERE ca.PostId IS NOT NULL
)
-- Final query with complex predicates, joins, and calculations
SELECT 
    fa.PostId,
    fa.Title,
    fa.Score,
    fa.ViewCount,
    fa.AnswerCount,
    fa.CommentCount,
    fa.CreationDate,
    fa.LastActivityDate,
    fa.OwnerUserId,
    fa.PostType,
    fa.OwnerName,
    fa.Reputation,
    fa.PostCount,
    fa.UserTotalScore,
    fa.UserAvgScore,
    fa.BadgeCount,
    fa.UserStatus,
    fa.PrimaryTag,
    fa.QualityLevel,
    fa.EngagementScore,
    fa.ScoreVsAvg,
    fa.AdjustedScore,
    fa.PostSummary,
    fa.RankByAdjustedScore,
    fa.MovingAvgScore,
    fa.BetterPostsCount,
    fa.PostCategory,
    fa.NormalizedScore,
    fa.VoteCount,
    fa.HighPerformanceIndicator,
    -- Additional complex string operations and conditional logic
    CASE 
        WHEN fa.Score > 10000 THEN 'Ultra-Viral'
        WHEN fa.Score > 5000 THEN 'Very Popular'
        WHEN fa.Score > 1000 THEN 'Popular'
        WHEN fa.Score > 100 THEN 'Noticeable'
        WHEN fa.Score > 0 THEN 'Small'
        ELSE 'Negative'
    END as ViralityLevel,
    -- Complex aggregate functions
    COUNT(fa.PostId) OVER () as TotalPosts,
    AVG(fa.Score) OVER () as AvgScoreAcrossAllPosts,
    MAX(fa.Score) OVER () as MaxScore,
    MIN(fa.Score) OVER () as MinScore,
    -- Filtering with complex conditions 
    CASE 
        WHEN fa.OwnerUserId IS NOT NULL 
        AND fa.Reputation > 500 
        AND fa.PostCount > 10 
        AND fa.UserTotalScore > 100 
        AND fa.Score > 50 
        THEN 'Qualified'
        ELSE 'Unqualified'
    END as QualificationStatus,
    -- Mathematical and statistical operations
    sqrt(fa.Score - COALESCE((SELECT AVG(Score) FROM Posts), 0)) as ScoreDeviation,
    -- Date and time manipulations
    EXTRACT(DAY FROM AGE(NOW(), fa.CreationDate)) as DaysOld,
    EXTRACT(YEAR FROM AGE(NOW(), fa.CreationDate)) as YearsOld,
    -- Concatenation with NULL-safe COALESCE
    COALESCE(fa.BadgesEarned, 'No Badges') as BadgeList,
    -- String functions and conditions
    CASE 
        WHEN fa.Tags IS NOT NULL AND LENGTH(fa.Tags) > 0 THEN
            LENGTH(fa.Tags) - LENGTH(REPLACE(fa.Tags, '><', '')) + 1
        ELSE 0
    END as TagCountAlt,
    -- Set operations and unioning
    1 as IsSelectedPost
FROM FinalAnalysis fa
WHERE
    fa.PostId IS NOT NULL 
    AND fa.Score IS NOT NULL 
    AND (fa.Reputation IS NULL OR fa.Reputation >= 100)
    AND (fa.OwnerUserId IS NULL OR fa.OwnerUserId > 0)
    AND (fa.PostType IS NOT NULL OR fa.PostType IN ('Question', 'Answer'))
    AND fa.Score >= -500  -- Filter out extreme negative scores
    AND fa.CreatedDate BETWEEN '2010-01-01'::timestamp AND '2023-12-31'::timestamp
    AND (fa.IsTrending = 1 OR fa.TagCount > 0 OR fa.Score > 100)
    AND (fa.PrimaryTag = 'sql' OR fa.PrimaryTag = 'javascript' OR fa.PrimaryTag = 'python' OR fa.PrimaryTag = 'c#')

UNION ALL

-- Second part of union with different criteria
SELECT 
    fa.PostId,
    '--- SUMMARY ---' as Title,
    SUM(fa.Score) as Score,
    SUM(fa.ViewCount) as ViewCount,
    SUM(fa.AnswerCount) as AnswerCount,
    SUM(fa.CommentCount) as CommentCount,
    MIN(fa.CreationDate) as CreationDate,
    MAX(fa.LastActivityDate) as LastActivityDate,
    NULL as OwnerUserId,
    'Summary' as PostType,
    'All Posts' as OwnerName,
    AVG(fa.Reputation) as Reputation,
    COUNT(DISTINCT fa.PostId) as PostCount,
    SUM(fa.UserTotalScore) as UserTotalScore,
    AVG(fa.UserAvgScore) as UserAvgScore,
    SUM(fa.BadgeCount) as BadgeCount,
    'Summary' as UserStatus,
    'AllTags' as PrimaryTag,
    'Summary' as QualityLevel,
    SUM(fa.EngagementScore) as EngagementScore,
    AVG(fa.ScoreVsAvg) as ScoreVsAvg,
    AVG(fa.AdjustedScore) as AdjustedScore,
    'Post Summary Total' as PostSummary,
    0 as RankByAdjustedScore,
    AVG(fa.MovingAvgScore) as MovingAvgScore,
    COUNT(*) as BetterPostsCount,
    'Summary' as PostCategory,
    AVG(fa.NormalizedScore) as NormalizedScore,
    SUM(fa.VoteCount) as VoteCount,
    AVG(fa.HighPerformanceIndicator) as HighPerformanceIndicator,
    'Summary' as ViralityLevel,
    1 as TotalPosts,
    AVG(fa.Score) as AvgScoreAcrossAllPosts,
    MAX(fa.Score) as MaxScore,
    MIN(fa.Score) as MinScore,
    'Summary' as QualificationStatus,
    NULL as ScoreDeviation,
    NULL as DaysOld,
    NULL as YearsOld,
    'Summary' as BadgeList,
    NULL as TagCountAlt,
    2 as IsSelectedPost
FROM FinalAnalysis fa
WHERE
    fa.PostId IS NOT NULL 
    AND fa.Score IS NOT NULL 
    AND fa.Reputation >= 100
    AND fa.PostType IS NOT NULL
GROUP BY fa.PostId
HAVING 
    COUNT(fa.PostId) > 0
    AND SUM(fa.Score) > 0
    AND COUNT(fa.Score) >= 5
ORDER BY 
    CASE WHEN IsSelectedPost = 1 THEN 1 ELSE 2 END,
    Score DESC,
    PostId ASC
LIMIT 10000;