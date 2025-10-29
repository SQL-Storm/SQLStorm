-- {"query": "7636.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2087} 
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
        STRING_AGG(DISTINCT p.PostTypeId::TEXT, ',') FILTER (WHERE p.PostTypeId IS NOT NULL) as PostTypes,
        AVG(p.Score) as AvgScore,
        CASE 
            WHEN u.Views > 0 THEN (u.UpVotes::FLOAT / u.Views * 100)
            ELSE 0 
        END as UpVoteRatio,
        (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 1 AND p2.ViewCount > 1000) as PopularQuestions
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TopPosts AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        STRING_AGG(DISTINCT pt.Name, ', ') as PostTypeName,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) as ScoreRank,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.ViewCount DESC) as ViewRank,
        RANK() OVER (ORDER BY p.CreationDate DESC) as RecentRank,
        CASE 
            WHEN p.ViewCount > 1000 THEN 'High'
            WHEN p.ViewCount > 500 THEN 'Medium'
            ELSE 'Low'
        END as Popularity
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.PostTypeId IN (1, 2) 
        AND p.CreationDate >= '2020-01-01'
        AND (p.ViewCount > 100 OR p.Score > 50)
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, p.OwnerUserId, p.PostTypeId, p.Tags, p.AnswerCount, p.CommentCount
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsRequired,
        t.IsModeratorOnly,
        CASE 
            WHEN t.Count > 1000 THEN 'Very Popular'
            WHEN t.Count > 100 THEN 'Popular'
            WHEN t.Count > 10 THEN 'Moderate'
            ELSE 'Rare'
        END as TagPopularity,
        COUNT(DISTINCT p.Id) as RelatedPosts,
        MAX(p.CreationDate) as LastPostDate
    FROM Tags t
    LEFT JOIN Posts p ON p.Tags ILIKE '%' || t.TagName || '%'
    GROUP BY t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId, t.IsRequired, t.IsModeratorOnly
),
UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        COUNT(v.Id) as VoteCount,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.PostId END) as UpVotesGiven,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.PostId END) as DownVotesGiven,
        COUNT(DISTINCT v.PostId) as PostsVoted,
        MAX(v.CreationDate) as LastVoteDate,
        AVG(v.CreationDate - LAG(v.CreationDate) OVER (PARTITION BY u.Id ORDER BY v.CreationDate)) as AvgTimeBetweenVotes
    FROM Users u
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.Reputation > 500
    GROUP BY u.Id, u.DisplayName
)
SELECT 
    'Performance Benchmark Report' as ReportTitle,
    COUNT(DISTINCT us.UserId) as TotalActiveUsers,
    COUNT(DISTINCT tp.PostId) as TotalPosts,
    COUNT(DISTINCT ta.TagName) as TotalTags,
    COUNT(DISTINCT ua.UserId) as TotalVotingUsers,
    
    -- Complex Window Function Analysis
    AVG(us.Reputation) as AvgReputation,
    MAX(us.Reputation) as MaxReputation,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY us.Reputation) as MedianReputation,
    
    -- Correlated Subqueries in Select
    (SELECT AVG(Reputation) FROM Users u2 WHERE u2.Views > 1000) as AvgReputationOfActiveUsers,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.Score > 100 AND p2.CreationDate >= CURRENT_DATE - INTERVAL '30 days') as RecentHighScorePosts,
    
    -- String Operations and Concatenations
    STRING_AGG(DISTINCT us.PostTypes, '; ') as UniquePostTypes,
    CONCAT('Tags: ', STRING_AGG(DISTINCT ta.TagName, ', ')) as TagSummary,
    
    -- Complex Predicates and Calculations
    CASE 
        WHEN COUNT(DISTINCT us.UserId) > 1000 AND COUNT(DISTINCT tp.PostId) > 5000 
        THEN 'High Volume Data Set'
        WHEN COUNT(DISTINCT us.UserId) > 500 AND COUNT(DISTINCT tp.PostId) > 2000
        THEN 'Medium Volume Data Set'
        ELSE 'Low Volume Data Set'
    END as DataVolumeClassification,
    
    -- Set Operators and Aggregations
    COUNT(DISTINCT CASE WHEN tp.Popularity = 'High' THEN tp.PostId END) as HighPopularityPosts,
    COUNT(DISTINCT CASE WHEN tp.Popularity = 'Medium' THEN tp.PostId END) as MediumPopularityPosts,

    -- NULL handling and COALESCE
    COALESCE(SUM(tp.ViewCount), 0) as TotalViews,
    COALESCE(SUM(tp.Score), 0) as TotalScore,
    SUM(CASE WHEN tp.ViewCount IS NULL THEN 1 ELSE 0 END) as PostsMissingViewCount,
    
    -- Advanced Calculations
    (CASE 
        WHEN COUNT(DISTINCT tp.PostId) > 0 
        THEN ROUND(SUM(tp.ViewCount) * 1.0 / COUNT(DISTINCT tp.PostId), 2)
        ELSE 0 
    END) as AvgViewsPerPost,
    
    -- Date/Time Calculations
    EXTRACT(YEAR FROM MAX(tp.CreationDate)) as LatestPostYear,
    EXTRACT(MONTH FROM MAX(tp.CreationDate)) as LatestPostMonth,
    
    -- Complex Grouping Logic
    STRING_AGG(DISTINCT CASE 
        WHEN us.UpVoteRatio > 50 THEN 'HighUpVoteRatio'
        WHEN us.UpVoteRatio > 25 THEN 'MediumUpVoteRatio'
        ELSE 'LowUpVoteRatio'
    END, ', ') as UserActivityLevels,
    
    -- Multiple Joins and Complex Relationships
    COUNT(DISTINCT CASE WHEN ta.TagPopularity = 'Very Popular' THEN ta.TagName END) as VeryPopularTagCount,
    COUNT(DISTINCT CASE WHEN ta.TagPopularity = 'Popular' THEN ta.TagName END) as PopularTagCount,
    
    -- Mathematical Expressions
    ROUND(AVG(CASE WHEN us.ViewCount > 0 THEN us.UpVotes * 100.0 / us.ViewCount ELSE 0 END), 2) as AvgUpVoteEfficiency,
    
    -- Conditional Aggregations with CASE
    SUM(CASE 
        WHEN tp.PostTypeId = 1 AND tp.ViewCount > 1000 THEN 1
        WHEN tp.PostTypeId = 2 AND tp.Score > 50 THEN 1
        ELSE 0 
    END) as QualifyingPosts,
    
    -- Complex CTE Join Patterns
    STRING_AGG(DISTINCT us.DisplayName, '; ') as UserNames,
    STRING_AGG(DISTINCT tp.Title, '; ') as PostTitles,
    STRING_AGG(DISTINCT ta.TagName, '; ') as TagNames
    
FROM UserStats us
FULL OUTER JOIN TopPosts tp ON us.UserId = tp.OwnerUserId
LEFT JOIN TagAnalysis ta ON ta.RelatedPosts > 0
LEFT JOIN UserActivity ua ON us.UserId = ua.UserId
WHERE (us.UserId IS NOT NULL OR tp.PostId IS NOT NULL OR ta.TagName IS NOT NULL)
GROUP BY 
    EXTRACT(YEAR FROM MAX(tp.CreationDate)),
    EXTRACT(MONTH FROM MAX(tp.CreationDate)),
    CASE 
        WHEN COUNT(DISTINCT us.UserId) > 1000 AND COUNT(DISTINCT tp.PostId) > 5000 
        THEN 'High Volume Data Set'
        WHEN COUNT(DISTINCT us.UserId) > 500 AND COUNT(DISTINCT tp.PostId) > 2000
        THEN 'Medium Volume Data Set'
        ELSE 'Low Volume Data Set'
    END
HAVING 
    COUNT(DISTINCT us.UserId) > 10 
    OR COUNT(DISTINCT tp.PostId) > 50 
    OR COUNT(DISTINCT ta.TagName) > 100
ORDER BY 
    TotalActiveUsers DESC,
    TotalPosts DESC,
    TotalTags DESC
LIMIT 1000;