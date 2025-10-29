-- {"query": "7677.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2822} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.CreationDate,
        u.DisplayName,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.CreationDate DESC) as RecentPostRank,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 THEN AVG(p.Score) 
            ELSE 0 
        END as AvgPostScore,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') as AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2010-01-01'
    GROUP BY u.Id, u.Reputation, u.CreationDate, u.DisplayName
),
TagComplexityAnalysis AS (
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'High'
            WHEN t.Count > 100 THEN 'Medium' 
            ELSE 'Low'
        END as PopularityLevel,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as PopularityRank,
        LAG(t.Count) OVER (ORDER BY t.Count DESC) - t.Count as PopularityDifference
    FROM Tags t
    WHERE t.TagName IS NOT NULL AND t.TagName != ''
),
PostComplexityMetrics AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        LEN(p.Body) as BodyLength,
        LEN(p.Title) as TitleLength,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN 
                (SELECT COUNT(*) FROM STRING_SPLIT(SUBSTRING(p.Tags, 2, LEN(p.Tags)-2), '><'))
            ELSE 0 
        END as TagCount,
        CASE 
            WHEN p.ParentId IS NOT NULL THEN 'Answer'
            WHEN p.PostTypeId = 1 THEN 'Question'
            ELSE 'Other'
        END as PostCategory,
        DATEDIFF(day, p.CreationDate, GETDATE()) as AgeInDays,
        CASE 
            WHEN p.Score > 100 THEN 'HighlyVoted'
            WHEN p.Score > 10 THEN 'ModeratelyVoted'
            ELSE 'LowVoted'
        END as VoteLevel,
        CASE 
            WHEN ABS(p.Score) > 50 THEN ABS(p.Score) 
            ELSE NULL 
        END as SignificantScore
    FROM Posts p
    WHERE p.CreationDate >= '2015-01-01'
),
UserEngagementScores AS (
    SELECT 
        u.Id,
        u.Reputation,
        COALESCE(u.UpVotes, 0) - COALESCE(u.DownVotes, 0) as NetVotes,
        COALESCE(u.Views, 0) as TotalViews,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Elite'
            WHEN u.Reputation > 1000 THEN 'Veteran'
            ELSE 'Regular'
        END as RepStatus,
        ROW_NUMBER() OVER (ORDER BY (COALESCE(u.UpVotes, 0) - COALESCE(u.DownVotes, 0)) DESC) as RepRank,
        NTILE(10) OVER (ORDER BY (COALESCE(u.UpVotes, 0) - COALESCE(u.DownVotes, 0))) as RepQuartile,
        COUNT(DISTINCT v.Id) as TotalVotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) as UpVotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) as DownVotes
    FROM Users u
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY u.Id, u.Reputation, u.UpVotes, u.DownVotes
),
TemporalPostAnalysis AS (
    SELECT 
        p.Id,
        p.ParentId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        DATEPART(year, p.CreationDate) as PostYear,
        DATEPART(month, p.CreationDate) as PostMonth,
        DATEPART(quarter, p.CreationDate) as PostQuarter,
        CASE 
            WHEN p.CreationDate >= '2020-01-01' THEN 'Recent'
            WHEN p.CreationDate >= '2015-01-01' THEN 'Mid'
            ELSE 'Legacy'
        END as TimePeriod,
        ROW_NUMBER() OVER (PARTITION BY DATEPART(year, p.CreationDate), DATEPART(month, p.CreationDate) ORDER BY p.CreationDate) as MonthlyPostSequence,
        LAG(p.Score) OVER (PARTITION BY DATEPART(year, p.CreationDate), DATEPART(month, p.CreationDate) ORDER BY p.CreationDate) as PreviousScoreInMonth
    FROM Posts p
    WHERE p.CreationDate >= '2014-01-01'
)
SELECT 
    'Performance Benchmark Report' as ReportHeader,
    COUNT(DISTINCT u.Id) as TotalUsers,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(DISTINCT c.Id) as TotalComments,
    COUNT(DISTINCT b.Id) as TotalBadges,
    (SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId = 1 AND p.CreationDate >= '2020-01-01') as RecentQuestions,
    (SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId = 2 AND p.CreationDate >= '2020-01-01') as RecentAnswers,
    (SELECT AVG(SignificantScore) FROM PostComplexityMetrics WHERE SignificantScore IS NOT NULL) as AvgHighValueScore,
    (SELECT AVG((SELECT COUNT(*) FROM STRING_SPLIT(SUBSTRING(p.Tags, 2, LEN(p.Tags)-2), '><'))) FROM Posts p WHERE p.Tags IS NOT NULL AND p.Tags != '') as AvgTagCount,
    (SELECT AVG(LEN(p.Body)) FROM Posts p WHERE p.Body IS NOT NULL) as AvgPostBodyLength,
    (SELECT COUNT(*) FROM Posts p WHERE p.ViewCount > 10000 AND p.Score > 50) as HighTrafficHighVotedPosts,
    (SELECT COUNT(*) FROM Users u WHERE u.Reputation > 10000) as EliteUsers,
    (SELECT COUNT(*) FROM Users u WHERE u.Reputation BETWEEN 1000 AND 10000) as VeteranUsers,
    (SELECT MAX(CreationDate) FROM Posts) as LatestPostDate,
    (SELECT MIN(CreationDate) FROM Posts) as EarliestPostDate,
    (SELECT COUNT(*) FROM Tags t WHERE t.Count > 1000) as PopularTags,
    (SELECT COUNT(*) FROM Tags t WHERE t.Count BETWEEN 100 AND 1000) as ModerateTags,
    (SELECT COUNT(*) FROM Tags t WHERE t.Count < 100) as LessPopularTags,
    
    -- Correlated subquery and calculated fields
    (SELECT COUNT(*) 
     FROM Users u2 
     WHERE u2.Reputation > (
         SELECT AVG(Reputation) 
         FROM Users u3 
         WHERE u3.Id IN (
             SELECT v.UserId 
             FROM Votes v 
             WHERE v.VoteTypeId IN (2, 3)
         )
     )
    ) as UsersAboveReputationAverage,
    
    -- Window function with complex partitioning and ranking
    (SELECT COUNT(*) 
     FROM (
         SELECT 
             u.Id,
             u.Reputation,
             ROW_NUMBER() OVER (PARTITION BY u.Reputation ORDER BY u.CreationDate DESC) as RepRank,
             DENSE_RANK() OVER (ORDER BY u.Reputation DESC) as RepDenseRank,
             NTILE(4) OVER (ORDER BY u.Reputation DESC) as RepQuartile,
             LAG(u.Reputation) OVER (ORDER BY u.Reputation DESC) as PreviousRep
         FROM Users u
         WHERE u.Reputation > 10000
     ) ranked_users 
     WHERE ranked_users.RepRank = 1
    ) as TopRankedUsers,
    
    -- Complex set operator and aggregate with grouping
    (SELECT COUNT(*) FROM (
        SELECT DISTINCT u.Id FROM Users u JOIN Posts p ON u.Id = p.OwnerUserId WHERE p.CreationDate >= '2019-01-01'
        EXCEPT
        SELECT DISTINCT u.Id FROM Users u JOIN Posts p ON u.Id = p.OwnerUserId WHERE p.CreationDate < '2019-01-01'
    ) users_with_new_posts) as ActiveUsersInRecentPeriod,
    
    -- NULL handling and CASE expressions
    (SELECT COUNT(*) 
     FROM Posts p 
     WHERE COALESCE(p.ClosedDate, '1900-01-01') = '1900-01-01' 
       AND COALESCE(p.CommunityOwnedDate, '1900-01-01') = '1900-01-01'
       AND p.PostTypeId IN (1, 2)
    ) as OpenPostsCount,
    
    -- String manipulation and concatenation
    (SELECT STRING_AGG(CONCAT(t.TagName, ':', t.Count), '; ') 
     FROM Tags t 
     WHERE t.Count > 1000
     ORDER BY t.Count DESC
    ) as PopularTagsConcatenated,
    
    -- Complex predicates and multiple joins
    (SELECT COUNT(DISTINCT u.Id) 
     FROM Users u
     INNER JOIN Posts p ON u.Id = p.OwnerUserId
     INNER JOIN PostHistory ph ON p.Id = ph.PostId
     INNER JOIN Badges b ON u.Id = b.UserId
     WHERE p.CreationDate BETWEEN '2018-01-01' AND '2020-12-31'
       AND b.Date BETWEEN '2018-01-01' AND '2020-12-31'
       AND ph.CreationDate BETWEEN '2018-01-01' AND '2020-12-31'
    ) as MultiActivityUsers,
    
    -- Date calculations and conditional logic
    (SELECT AVG(DATEDIFF(day, p.CreationDate, GETDATE())) 
     FROM Posts p 
     WHERE p.PostTypeId = 1 
       AND p.CreationDate >= '2016-01-01'
       AND p.CreationDate <= '2020-12-31'
    ) as AvgQuestionAge,
    
    -- Outer join and aggregation
    (SELECT COUNT(*) 
     FROM (
         SELECT u.Id 
         FROM Users u
         LEFT JOIN Posts p ON u.Id = p.OwnerUserId
         LEFT JOIN Comments c ON u.Id = c.UserId
         WHERE p.Id IS NULL 
           AND c.Id IS NULL
           AND u.CreationDate >= '2019-01-01'
         GROUP BY u.Id
     ) inactive_users
    ) as InactiveUsers,
    
    -- Cross-table calculations with CTE references
    (SELECT MAX(RepStatus) 
     FROM UserEngagementScores) as TopRepStatus,
    
    -- Multiple subqueries with string operations
    (SELECT SUBSTRING(
        (SELECT '; ' + t.TagName 
         FROM Tags t 
         WHERE t.Count > 500 
         ORDER BY t.Count DESC 
         FOR XML PATH('')), 
        3, 1000
    ) as TopTagList,
    
    -- Complex filtering and set operations
    (SELECT COUNT(*) 
     FROM (
         SELECT p.Id 
         FROM Posts p
         WHERE p.Score > (SELECT AVG(Score) FROM Posts)
           AND p.AnswerCount > 1
           AND EXISTS (
               SELECT 1 
               FROM PostHistory ph 
               WHERE ph.PostId = p.Id 
                 AND ph.PostHistoryTypeId IN (1, 2, 3)
           )
           AND NOT EXISTS (
               SELECT 1 
               FROM Comments c 
               WHERE c.PostId = p.Id 
                 AND c.Score < 0
           )
         INTERSECT
         SELECT p.Id 
         FROM Posts p
         WHERE p.PostTypeId = 1 
           AND p.Title LIKE '%question%'
           AND p.ViewCount > 1000
     ) qualified_posts
    ) as QualifiedPostsCount,
    
    -- Final timestamp for benchmarking
    GETDATE() as BenchmarkTimestamp