-- {"query": "7626.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1942} 
WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.ViewCount,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        AVG(p.Score) as AvgPostScore,
        MAX(p.CreationDate) as LastPostDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as ReputationRank,
        CASE 
            WHEN u.Reputation >= 10000 THEN 'Diamond'
            WHEN u.Reputation >= 5000 THEN 'Platinum'
            WHEN u.Reputation >= 1000 THEN 'Gold'
            WHEN u.Reputation >= 500 THEN 'Silver'
            WHEN u.Reputation >= 100 THEN 'Bronze'
            ELSE 'Copper'
        END as ReputationTier
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.AccountId IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.ViewCount
),
PostAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.Tags,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END as PostType,
        COALESCE(p.Tags, '') as CleanTags,
        CASE 
            WHEN p.Score > 100 THEN 'HighlyVoted'
            WHEN p.Score > 50 THEN 'ModeratelyVoted'
            WHEN p.Score > 10 THEN 'LowVoted'
            ELSE 'Unvoted'
        END as VoteCategory,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevScore,
        LEAD(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as NextScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as UserPostRank,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) as GlobalScoreRank
    FROM Posts p
    WHERE p.CreationDate >= DATEADD(YEAR, -2, GETDATE())
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            WHEN t.Count > 10 THEN 'Niche'
            ELSE 'Obscure'
        END as TagPopularity,
        PERCENT_RANK() OVER (ORDER BY t.Count) as PopularityPercentile,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as PopularityRank
    FROM Tags t
    WHERE t.TagName IS NOT NULL
),
UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.CreationDate as UserCreated,
        COUNT(DISTINCT ph.Id) as HistoryCount,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (1, 4, 5, 6) THEN 1 END) as EditCount,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13) THEN 1 END) as StatusChangeCount,
        MAX(ph.CreationDate) as LastActivity,
        DATEDIFF(DAY, u.CreationDate, GETDATE()) as DaysActive
    FROM Users u
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
        AND ph.CreationDate >= DATEADD(YEAR, -1, GETDATE())
    GROUP BY u.Id, u.DisplayName, u.CreationDate
)
SELECT 
    'Performance Benchmark Query Results' as QueryDescription,
    COUNT(DISTINCT us.UserId) as TotalUsers,
    COUNT(DISTINCT pa.PostId) as TotalPosts,
    COUNT(DISTINCT ta.TagName) as TotalTags,
    COUNT(DISTINCT ua.UserId) as ActiveUsers,
    AVG(us.AvgPostScore) as AvgUserPostScore,
    MAX(pa.GlobalScoreRank) as MaxScoreRank,
    STRING_AGG(DISTINCT SUBSTRING(ta.TagName, 1, 10), ', ') as SampleTags,
    COUNT(*) as TotalRecordsProcessed,
    DATEDIFF(DAY, MIN(us.LastPostDate), MAX(us.LastPostDate)) as TimeSpanDays,
    CASE 
        WHEN AVG(us.Reputation) > 10000 THEN 'HighlyActive'
        WHEN AVG(us.Reputation) > 5000 THEN 'Active'
        WHEN AVG(us.Reputation) > 1000 THEN 'Moderate'
        ELSE 'Beginner'
    END as CommunityStatus,
    COUNT(CASE WHEN pa.PostTypeId = 1 THEN 1 END) as QuestionCount,
    COUNT(CASE WHEN pa.PostTypeId = 2 THEN 1 END) as AnswerCount
FROM UserStats us
FULL OUTER JOIN PostAnalysis pa ON us.UserId = pa.OwnerUserId
FULL OUTER JOIN TagAnalysis ta ON ta.TagName LIKE '%' + LEFT(pa.Tags, 5) + '%'
FULL OUTER JOIN UserActivity ua ON us.UserId = ua.UserId
WHERE (
    (us.UserId IS NOT NULL AND us.Reputation > 100) 
    OR (pa.PostId IS NOT NULL AND pa.Score > 0)
    OR (ta.TagName IS NOT NULL AND ta.TagCount > 10)
)
AND (CASE WHEN pa.CreationDate IS NULL THEN 0 ELSE 1 END) = 1
AND (
    (us.ReputationTier IN ('Gold', 'Platinum', 'Diamond') 
    OR pa.VoteCategory IN ('HighlyVoted', 'ModeratelyVoted')
    OR ta.TagPopularity IN ('Popular', 'Moderate'))
    OR (ua.DaysActive > 365 AND ua.HistoryCount > 100)
)
AND (COALESCE(pa.Score, 0) + COALESCE(us.AvgPostScore, 0) + COALESCE(ta.TagCount, 0)) > 0
AND (
    CASE 
        WHEN pa.Tags IS NOT NULL AND pa.Tags != '' THEN 
            CASE WHEN pa.Tags LIKE '%<%' THEN 1 ELSE 0 END
        ELSE 0 
    END = 1
    OR us.Reputation IS NOT NULL
    OR ta.TagCount IS NOT NULL
)
AND (pa.PostId IS NULL OR pa.CreationDate > DATEADD(MONTH, -6, GETDATE()))
AND (us.UserId IS NULL OR us.LastPostDate > DATEADD(YEAR, -3, GETDATE()))
ORDER BY 
    COALESCE(us.Reputation, 0) DESC,
    COALESCE(pa.Score, 0) DESC,
    COALESCE(ta.TagCount, 0) DESC
OFFSET 100 ROWS FETCH NEXT 1000 ROWS ONLY
UNION ALL
SELECT 
    'Performance Benchmark Query Results (Alternative Calculation)',
    COUNT(DISTINCT u.Id),
    COUNT(DISTINCT p.Id),
    COUNT(DISTINCT t.Id),
    COUNT(DISTINCT CASE WHEN u.LastAccessDate > DATEADD(DAY, -30, GETDATE()) THEN u.Id END),
    AVG(CAST(p.Score AS FLOAT)),
    NULL,
    NULL,
    COUNT(*) as TotalRecords,
    DATEDIFF(DAY, MIN(u.CreationDate), MAX(u.CreationDate)),
    'Mixed',
    COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END),
    COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END)
FROM Users u
INNER JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Tags t ON p.Tags LIKE '%' + t.TagName + '%'
WHERE u.Reputation BETWEEN 100 AND 10000
AND u.CreationDate >= DATEADD(YEAR, -5, GETDATE())
AND (
    (p.Score > 50 AND p.ViewCount > 100)
    OR (p.CreationDate > DATEADD(MONTH, -6, GETDATE()) AND p.AnswerCount > 0)
)
AND COALESCE(p.Body, '') != ''
GROUP BY 
    CASE WHEN u.Reputation > 5000 THEN 'High' ELSE 'Low' END,
    CASE WHEN p.Score > 100 THEN 'HighScore' ELSE 'LowScore' END
HAVING 
    COUNT(DISTINCT p.Id) > 50
    AND AVG(CAST(p.Score AS FLOAT)) > 5
ORDER BY 
    SUM(p.Score) DESC
LIMIT 5000;