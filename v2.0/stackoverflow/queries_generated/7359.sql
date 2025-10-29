-- {"query": "7359.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2236} 
WITH UserStats AS (
    SELECT 
        u.Id,
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
        MAX(p.LastActivityDate) as LastActivityDate,
        STRING_AGG(DISTINCT p.Tags, '; ') as AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2010-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        COALESCE(p1.Title, 'No Title') as ExcerptTitle,
        COALESCE(p2.Title, 'No Title') as WikiTitle,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            ELSE 'Niche'
        END as PopularityLevel,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as TagRank,
        NTILE(10) OVER (ORDER BY t.Count DESC) as TagDecile
    FROM Tags t
    LEFT JOIN Posts p1 ON t.ExcerptPostId = p1.Id
    LEFT JOIN Posts p2 ON t.WikiPostId = p2.Id
),
PostActivity AS (
    SELECT 
        p.Id,
        p.Title,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.LastActivityDate,
        p.OwnerUserId,
        p.Tags,
        p.ParentId,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END as PostTypeDesc,
        DATEDIFF(day, p.CreationDate, p.LastActivityDate) as DaysActive,
        CASE 
            WHEN p.Score > 100 THEN 'Highly_Voted'
            WHEN p.Score > 25 THEN 'Moderately_Voted'
            WHEN p.Score > 0 THEN 'Low_Voted'
            ELSE 'Unvoted'
        END as VoteCategory,
        COALESCE(
            (SELECT COUNT(*) 
             FROM PostHistory ph 
             WHERE ph.PostId = p.Id 
             AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)),
            0
        ) as EditCount
    FROM Posts p
    WHERE p.CreationDate >= '2015-01-01'
),
UserPerformance AS (
    SELECT 
        us.Id,
        us.DisplayName,
        us.Reputation,
        us.PostCount,
        us.CommentCount,
        us.BadgeCount,
        us.AvgPostScore,
        DENSE_RANK() OVER (ORDER BY us.Reputation DESC) as ReputationRank,
        PERCENT_RANK() OVER (ORDER BY us.PostCount DESC) as PostPerformancePercentile,
        CASE 
            WHEN us.PostCount > 100 THEN 'Elite'
            WHEN us.PostCount > 50 THEN 'Veteran'
            WHEN us.PostCount > 10 THEN 'Active'
            ELSE 'Beginner'
        END as UserLevel
    FROM UserStats us
),
ComplexAnalysis AS (
    SELECT 
        pa.Id as PostId,
        pa.Title,
        pa.PostTypeDesc,
        pa.Score,
        pa.ViewCount,
        pa.AnswerCount,
        pa.CommentCount,
        pa.EditCount,
        pa.DaysActive,
        pa.VoteCategory,
        pa.OwnerUserId,
        ups.DisplayName as OwnerName,
        ups.ReputationRank,
        ups.PostPerformancePercentile,
        ups.UserLevel,
        ta.TagName,
        ta.Count as TagCount,
        ta.PopularityLevel,
        ta.TagRank,
        CASE 
            WHEN pa.ViewCount > (SELECT AVG(ViewCount) FROM Posts) THEN 'Above_Average'
            WHEN pa.ViewCount > (SELECT AVG(ViewCount) * 0.5 FROM Posts) THEN 'Below_Average'
            ELSE 'Poor_Performance'
        END as PerformanceCategory,
        CASE 
            WHEN pa.EditCount > 10 THEN 'Highly_Edited'
            WHEN pa.EditCount > 5 THEN 'Moderately_Edited'
            ELSE 'Low_Edited'
        END as EditLevel,
        ROW_NUMBER() OVER (PARTITION BY pa.OwnerUserId ORDER BY pa.Score DESC) as UserPostRank,
        LAG(pa.Score, 1) OVER (PARTITION BY pa.OwnerUserId ORDER BY pa.CreationDate) as PreviousScore,
        CASE 
            WHEN pa.Score > LAG(pa.Score, 1) OVER (PARTITION BY pa.OwnerUserId ORDER BY pa.CreationDate) THEN 'Improved'
            WHEN pa.Score < LAG(pa.Score, 1) OVER (PARTITION BY pa.OwnerUserId ORDER BY pa.CreationDate) THEN 'Declined'
            ELSE 'Stable'
        END as ScoreTrend,
        RANK() OVER (ORDER BY pa.DaysActive DESC) as ActivityRank,
        CUME_DIST() OVER (ORDER BY pa.Score DESC) as ScoreDistribution
    FROM PostActivity pa
    JOIN UserPerformance ups ON pa.OwnerUserId = ups.Id
    JOIN Tags ta ON ta.TagName = SPLIT_PART(pa.Tags, '><', 1)
    WHERE pa.CreationDate >= '2015-01-01'
)
SELECT 
    ca.PostId,
    ca.Title,
    ca.PostTypeDesc,
    ca.Score,
    ca.ViewCount,
    ca.AnswerCount,
    ca.CommentCount,
    ca.EditCount,
    ca.DaysActive,
    ca.VoteCategory,
    ca.OwnerName,
    ca.ReputationRank,
    ca.PostPerformancePercentile,
    ca.UserLevel,
    ca.TagName,
    ca.TagCount,
    ca.PopularityLevel,
    ca.TagRank,
    ca.PerformanceCategory,
    ca.EditLevel,
    ca.UserPostRank,
    ca.PreviousScore,
    ca.ScoreTrend,
    ca.ActivityRank,
    ca.ScoreDistribution,
    CASE 
        WHEN ca.ReputationRank <= 10 THEN 'Top_Performer'
        WHEN ca.PostPerformancePercentile > 0.9 THEN 'High_Performer'
        WHEN ca.Score > 50 THEN 'Good_Performer'
        ELSE 'Standard'
    END as FinalPerformanceTier,
    (ca.Score * ca.ViewCount * 0.1) + (ca.AnswerCount * 10) + (ca.CommentCount * 5) as CompositeScore,
    COALESCE(
        (SELECT COUNT(*) 
         FROM Votes v 
         WHERE v.PostId = ca.PostId 
         AND v.VoteTypeId BETWEEN 2 AND 3), 
        0
    ) as NetVotes,
    COALESCE(
        (SELECT COUNT(*) 
         FROM Comments c 
         WHERE c.PostId = ca.PostId), 
        0
    ) as TotalComments,
    CASE 
        WHEN ca.Score > (SELECT AVG(Score) FROM Posts) THEN 'Above_Average_Score'
        WHEN ca.Score < (SELECT AVG(Score) * 0.5 FROM Posts) THEN 'Below_Average_Score'
        ELSE 'Average_Score'
    END as ScoreClassification,
    DATEADD(day, 7, ca.CreationDate) as OneWeekLater,
    DATEADD(month, 1, ca.CreationDate) as OneMonthLater,
    DATEDIFF(day, ca.CreationDate, GETDATE()) as DaysSinceCreation,
    'Post_' + CAST(ca.PostId AS VARCHAR) + '_Analysis' as ReportTitle
FROM ComplexAnalysis ca
WHERE ca.Score IS NOT NULL
AND ca.ViewCount IS NOT NULL
AND ca.AnswerCount IS NOT NULL
AND ca.CommentCount IS NOT NULL
AND ca.EditCount IS NOT NULL
AND ca.OwnerName IS NOT NULL
AND EXISTS (
    SELECT 1 
    FROM Posts p 
    WHERE p.Id = ca.PostId 
    AND p.CreationDate >= '2015-01-01'
)
UNION ALL
SELECT 
    ca.PostId,
    'AGGREGATE_' + CAST(COUNT(*) AS VARCHAR) + '_POSTS' as Title,
    'AGGREGATE' as PostTypeDesc,
    SUM(ca.Score) as Score,
    SUM(ca.ViewCount) as ViewCount,
    SUM(ca.AnswerCount) as AnswerCount,
    SUM(ca.CommentCount) as CommentCount,
    SUM(ca.EditCount) as EditCount,
    AVG(ca.DaysActive) as DaysActive,
    'AGGREGATED' as VoteCategory,
    'SYSTEM' as OwnerName,
    MIN(ca.ReputationRank) as ReputationRank,
    AVG(ca.PostPerformancePercentile) as PostPerformancePercentile,
    'GROUPED' as UserLevel,
    STRING_AGG(DISTINCT ca.TagName, ', ') as TagName,
    AVG(ca.TagCount) as TagCount,
    'AGGREGATED' as PopularityLevel,
    MIN(ca.TagRank) as TagRank,
    'AGGREGATED' as PerformanceCategory,
    'AGGREGATED' as EditLevel,
    MIN(ca.UserPostRank) as UserPostRank,
    NULL as PreviousScore,
    'AGGREGATED' as ScoreTrend,
    MAX(ca.ActivityRank) as ActivityRank,
    AVG(ca.ScoreDistribution) as ScoreDistribution,
    SUM(ca.CompositeScore) as FinalPerformanceTier,
    AVG(ca.NetVotes) as CompositeScore,
    AVG(ca.TotalComments) as TotalComments,
    'AGGREGATED' as ScoreClassification,
    NULL as OneWeekLater,
    NULL as OneMonthLater,
    AVG(ca.DaysSinceCreation) as DaysSinceCreation,
    'SYSTEM_AGGR_' + CAST(COUNT(*) AS VARCHAR) + '_REPORTS' as ReportTitle
FROM ComplexAnalysis ca
GROUP BY ca.OwnerName
HAVING COUNT(*) > 1
ORDER BY ca.Score DESC, ca.ViewCount DESC;