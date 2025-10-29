-- {"query": "7941.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1704} 
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
            WHEN u.Views > 10000 THEN 'High'
            WHEN u.Views > 5000 THEN 'Medium'
            ELSE 'Low'
        END as EngagementLevel,
        CASE 
            WHEN u.Reputation > 100000 THEN 'Elite'
            WHEN u.Reputation > 50000 THEN 'Veteran'
            WHEN u.Reputation > 10000 THEN 'Experienced'
            ELSE 'Beginner'
        END as ReputationTier,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) as RepRank,
        AVG(p.Score) as AvgPostScore,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) as QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) as AnswerCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id > 0 AND u.AccountId IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TopQuestions AS (
    SELECT 
        p.Id as QuestionId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.OwnerUserId,
        p.CreationDate,
        u.DisplayName as OwnerName,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) as RankWithinUser,
        PERCENT_RANK() OVER (ORDER BY p.Score) as ScorePercentile,
        NTH_VALUE(p.Title, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as TopScoringTitle
    FROM Posts p
    INNER JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 AND p.Score > 0
),
CommunityEngagement AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.OwnerUserId,
        p.CreationDate,
        u.DisplayName as OwnerName,
        CASE 
            WHEN p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'AboveAverage'
            WHEN p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) * 0.5 THEN 'BelowAverage'
            ELSE 'Low'
        END as QualityLevel,
        DATEDIFF('day', p.CreationDate, CURRENT_TIMESTAMP) as AgeInDays,
        p.AnswerCount * 1.0 / NULLIF(p.ViewCount, 0) as AnswerToViewRatio,
        COALESCE(p.Tags, '') as Tags,
        CASE 
            WHEN p.Tags LIKE '%<javascript>%' OR p.Tags LIKE '%<python>%' OR p.Tags LIKE '%<java>%' THEN 'PopularTech'
            WHEN p.Tags LIKE '%<sql>%' OR p.Tags LIKE '%<database>%' THEN 'Database'
            WHEN p.Tags LIKE '%<algorithm>%' OR p.Tags LIKE '%<performance>%' THEN 'Computing'
            ELSE 'Other'
        END as TopicCategory
    FROM Posts p
    INNER JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 AND p.Score IS NOT NULL AND p.ViewCount IS NOT NULL
),
ModeratorStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(v.Id) as VoteCount,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) as UpvotesReceived,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) as DownvotesReceived,
        COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) as BookmarksReceived,
        AVG(CASE WHEN v.VoteTypeId = 2 THEN v.PostId ELSE NULL END) as AvgPostScoreReceived,
        STRING_AGG(CAST(v.VoteTypeId AS VARCHAR), ',') as VoteTypeHistory,
        LAG(u.Reputation, 1, 0) OVER (ORDER BY u.CreationDate) as PrevReputation,
        u.Reputation - LAG(u.Reputation, 1, 0) OVER (ORDER BY u.CreationDate) as RepChangeSincePrev
    FROM Users u
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.Id IN (
        SELECT DISTINCT OwnerUserId 
        FROM Posts p 
        WHERE p.PostTypeId = 1 AND p.Score > 1000
    )
    GROUP BY u.Id, u.DisplayName, u.Reputation
)
SELECT 
    'PerformanceBenchmarkResults' as QueryType,
    COUNT(*) as TotalRecords,
    COUNT(DISTINCT ua.UserId) as UniqueUsers,
    AVG(ua.Reputation) as AvgReputation,
    AVG(ua.PostCount) as AvgPostCount,
    AVG(ua.AvgPostScore) as AvgPostScore,
    COUNT(CASE WHEN ua.ReputationTier = 'Elite' THEN 1 END) as EliteUsers,
    COUNT(CASE WHEN ua.ReputationTier = 'Veteran' THEN 1 END) as VeteranUsers,
    COUNT(CASE WHEN ua.ReputationTier = 'Experienced' THEN 1 END) as ExperiencedUsers,
    COUNT(CASE WHEN ua.ReputationTier = 'Beginner' THEN 1 END) as BeginnerUsers,
    COUNT(CASE WHEN ua.EngagementLevel = 'High' THEN 1 END) as HighEngagementUsers,
    COUNT(CASE WHEN ua.EngagementLevel = 'Medium' THEN 1 END) as MediumEngagementUsers,
    COUNT(CASE WHEN ua.EngagementLevel = 'Low' THEN 1 END) as LowEngagementUsers,
    COUNT(CASE WHEN tq.ScorePercentile > 0.8 THEN 1 END) as Top80PercentQuestions,
    COUNT(CASE WHEN ce.AgeInDays < 30 THEN 1 END) as RecentPosts,
    COUNT(CASE WHEN ce.TopicCategory = 'PopularTech' THEN 1 END) as TechRelatedPosts,
    COUNT(CASE WHEN ce.TopicCategory = 'Database' THEN 1 END) as DatabasePosts,
    COUNT(CASE WHEN ce.TopicCategory = 'Computing' THEN 1 END) as ComputingPosts,
    COUNT(CASE WHEN ce.QualityLevel = 'AboveAverage' THEN 1 END) as AboveAveragePosts,
    SUM(CASE WHEN ms.RepChangeSincePrev > 10000 THEN 1 ELSE 0 END) as SignificantRepGrowth,
    AVG(CASE WHEN ms.RepChangeSincePrev > 0 THEN ms.RepChangeSincePrev END) as AvgRepGrowth,
    STRING_AGG(ua.ReputationTier, ';') as ReputationTiers,
    CONCAT('Total:', COUNT(*), ', Elite:', COUNT(CASE WHEN ua.ReputationTier = 'Elite' THEN 1 END)) as SummaryMetrics
FROM UserActivityStats ua
FULL OUTER JOIN TopQuestions tq ON 1=1
FULL OUTER JOIN CommunityEngagement ce ON 1=1
FULL OUTER JOIN ModeratorStats ms ON 1=1
WHERE ua.UserId IS NOT NULL 
   OR tq.QuestionId IS NOT NULL 
   OR ce.PostId IS NOT NULL 
   OR ms.UserId IS NOT NULL
HAVING COUNT(*) > 0
ORDER BY ua.Reputation DESC
LIMIT 1;