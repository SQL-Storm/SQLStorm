-- {"query": "7442.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2306} 
WITH UserStats AS (
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
            WHEN u.Reputation > 10000 THEN 'Elite'
            WHEN u.Reputation > 1000 THEN 'Veteran'
            WHEN u.Reputation > 100 THEN 'Member'
            ELSE 'Newbie'
        END as ReputationTier,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 100 THEN 'Highly Active'
            WHEN COUNT(DISTINCT p.Id) > 50 THEN 'Active'
            WHEN COUNT(DISTINCT p.Id) > 10 THEN 'Regular'
            ELSE 'Occasional'
        END as ActivityLevel
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
PostAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.OwnerUserId,
        p.PostTypeId,
        p.Tags,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            WHEN p.PostTypeId = 4 THEN 'TagWikiExcerpt'
            WHEN p.PostTypeId = 5 THEN 'TagWiki'
            WHEN p.PostTypeId = 6 THEN 'ModeratorNomination'
            ELSE 'Other'
        END as PostType,
        CASE 
            WHEN p.Score >= 100 THEN 'Hot'
            WHEN p.Score >= 25 THEN 'Popular'
            WHEN p.Score >= 0 THEN 'Neutral'
            WHEN p.Score >= -25 THEN 'Controversial'
            ELSE 'Negative'
        END as Popularity,
        COALESCE(p.AnswerCount, 0) + COALESCE(p.CommentCount, 0) as Engagement,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PreviousScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PostRank,
        NTILE(4) OVER (ORDER BY p.Score) as ScoreQuartile,
        DENSE_RANK() OVER (ORDER BY p.OwnerUserId) as UserRank
    FROM Posts p
    WHERE p.Id IS NOT NULL
),
UserTagAnalysis AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2) FILTER (WHERE p.Tags IS NOT NULL), ', ') as UserTags,
        COUNT(p.Id) as TaggedPosts,
        AVG(p.Score) as AvgTaggedPostScore,
        MAX(p.Score) as MaxTaggedPostScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.Tags IS NOT NULL
    WHERE u.Id > 0
    GROUP BY u.Id, u.DisplayName
),
TopPosts AS (
    SELECT 
        pa.PostId,
        pa.Title,
        pa.Score,
        pa.ViewCount,
        pa.OwnerUserId,
        pa.PostType,
        pa.Popularity,
        pa.Engagement,
        pa.PreviousScore,
        pa.PostRank,
        pa.ScoreQuartile,
        pa.UserRank,
        ROW_NUMBER() OVER (ORDER BY pa.Score DESC) as RankByScore,
        RANK() OVER (ORDER BY pa.Score DESC) as RankByScoreWithTies
    FROM PostAnalysis pa
    WHERE pa.PostId IS NOT NULL
),
RecentActivity AS (
    SELECT 
        p.Id,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        p.PostTypeId,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) as RecentRank
    FROM Posts p
    WHERE p.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '7 days'
),
TagStatistics AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count >= 1000 THEN 'Trending'
            WHEN t.Count >= 500 THEN 'Popular'
            WHEN t.Count >= 100 THEN 'Moderate'
            WHEN t.Count >= 10 THEN 'Niche'
            ELSE 'Rare'
        END as TagPopularity,
        LAG(t.Count, 1) OVER (ORDER BY t.Count DESC) as PreviousCount,
        PERCENT_RANK() OVER (ORDER BY t.Count) as CountPercentile,
        AVG(t.Count) OVER () as AvgTagCount,
        STDDEV(t.Count) OVER () as StdDevTagCount
    FROM Tags t
    WHERE t.TagName IS NOT NULL
)
SELECT 
    'Performance Benchmark Query Results' as QueryDescription,
    COUNT(DISTINCT us.UserId) as TotalUsers,
    COUNT(DISTINCT pa.PostId) as TotalPosts,
    COUNT(DISTINCT ta.UserId) as UsersWithTags,
    COUNT(DISTINCT tp.PostId) as TopPostsCount,
    COUNT(DISTINCT ra.Id) as RecentPosts,
    COUNT(DISTINCT ts.TagName) as TotalTags,
    AVG(us.Reputation) as AvgReputation,
    AVG(pa.Score) as AvgPostScore,
    AVG(pa.ViewCount) as AvgPostViews,
    MAX(us.Reputation) as MaxReputation,
    MIN(pa.Score) as MinPostScore,
    SUM(pa.ViewCount) as TotalViews,
    STRING_AGG(DISTINCT us.ReputationTier, ', ') as ReputationTiers,
    STRING_AGG(DISTINCT pa.Popularity, ', ') as PopularityLevels,
    STRING_AGG(DISTINCT us.ActivityLevel, ', ') as ActivityLevels,
    CASE 
        WHEN COUNT(DISTINCT CASE WHEN us.Reputation > 10000 THEN us.UserId END) > 0 THEN 'Has Elite Users'
        ELSE 'No Elite Users'
    END as EliteUsersIndicator,
    CASE 
        WHEN COUNT(DISTINCT CASE WHEN pa.Score >= 100 THEN pa.PostId END) > 0 THEN 'Has Hot Posts'
        ELSE 'No Hot Posts'
    END as HotPostsIndicator,
    CASE 
        WHEN AVG(pa.ViewCount) > 1000 THEN 'High Engagement Site'
        WHEN AVG(pa.ViewCount) > 500 THEN 'Moderate Engagement Site'
        ELSE 'Low Engagement Site'
    END as SiteEngagementLevel,
    'Benchmark completed at ' || CURRENT_TIMESTAMP as Timestamp,
    CASE 
        WHEN COUNT(DISTINCT tp.PostId) > 500 THEN 'Large Dataset'
        WHEN COUNT(DISTINCT tp.PostId) > 100 THEN 'Medium Dataset'
        ELSE 'Small Dataset'
    END as DatasetSize,
    STRING_AGG(
        CASE 
            WHEN tp.RankByScore <= 10 THEN 
                CONCAT('Rank-', tp.RankByScore, ': ', SUBSTRING(tp.Title, 1, 50), ' (Score: ', tp.Score, ')')
            ELSE NULL
        END, 
        ' | '
    ) FILTER (WHERE tp.RankByScore <= 10) as Top10Posts,
    STRING_AGG(DISTINCT ts.TagName, ', ') WITHIN GROUP (ORDER BY ts.Count DESC) as TopTagsByCount,
    COUNT(DISTINCT CASE WHEN ts.TagPopularity IN ('Trending', 'Popular') THEN ts.TagName END) as PopularTags,
    COUNT(DISTINCT CASE WHEN ts.TagPopularity = 'Rare' THEN ts.TagName END) as RareTags,
    AVG(CASE WHEN ts.Count > 0 THEN ts.Count ELSE 1 END) as AvgTagCountWithFallback,
    MIN(ts.Count) as MinTagCount,
    MAX(ts.Count) as MaxTagCount,
    ROUND(SDDEV(ts.Count), 2) as TagCountStandardDeviation
FROM UserStats us
FULL OUTER JOIN PostAnalysis pa ON us.UserId = pa.OwnerUserId
FULL OUTER JOIN UserTagAnalysis ta ON us.UserId = ta.UserId
FULL OUTER JOIN TopPosts tp ON pa.PostId = tp.PostId
FULL OUTER JOIN RecentActivity ra ON pa.PostId = ra.Id
FULL OUTER JOIN TagStatistics ts ON ts.TagName IS NOT NULL
WHERE 
    (us.UserId IS NOT NULL OR pa.PostId IS NOT NULL OR ta.UserId IS NOT NULL OR tp.PostId IS NOT NULL OR ra.Id IS NOT NULL OR ts.TagName IS NOT NULL)
    AND (
        CASE 
            WHEN us.UserId IS NOT NULL AND us.Reputation > 1000 THEN TRUE
            WHEN pa.PostId IS NOT NULL AND pa.Score >= 10 THEN TRUE
            WHEN ta.UserId IS NOT NULL AND ta.TaggedPosts > 5 THEN TRUE
            WHEN tp.PostId IS NOT NULL AND tp.Score >= 5 THEN TRUE
            WHEN ra.Id IS NOT NULL THEN TRUE
            WHEN ts.TagName IS NOT NULL THEN TRUE
            ELSE FALSE
        END
    )
    AND COALESCE(us.Reputation, 0) > 0
    AND COALESCE(pa.Score, 0) >= -100
    AND COALESCE(pa.ViewCount, 0) >= 0
    AND pa.CreationDate >= '2020-01-01 00:00:00'
    AND ts.Count >= 1
    AND CASE 
        WHEN pa.PostType IN ('Question', 'Answer') THEN TRUE
        WHEN pa.PostType IN ('Wiki', 'TagWiki') THEN TRUE
        ELSE FALSE
    END
    AND (
        CASE 
            WHEN us.ActivityLevel IN ('Highly Active', 'Active') THEN TRUE
            WHEN us.ActivityLevel IN ('Regular', 'Occasional') THEN TRUE
            ELSE FALSE
        END
    )
    AND (
        ta.UserTags IS NOT NULL 
        AND LENGTH(ta.UserTags) > 0
        AND ta.UserTags != ''
    )
ORDER BY (
    COALESCE(us.Reputation, 0) + 
    COALESCE(pa.Score, 0) + 
    COALESCE(pa.ViewCount, 0)
) DESC
LIMIT 1000;