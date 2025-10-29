-- {"query": "7064.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2110} 
WITH RECURSIVE PostHierarchy AS (
    SELECT 
        p.Id as PostId,
        p.ParentId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        0 as Level,
        CAST(p.Id AS VARCHAR(1000)) as Path
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.ParentId IS NULL
    
    UNION ALL
    
    SELECT 
        p.Id as PostId,
        p.ParentId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        ph.Level + 1 as Level,
        ph.Path || '->' || CAST(p.Id AS VARCHAR(1000)) as Path
    FROM Posts p
    INNER JOIN PostHierarchy ph ON p.ParentId = ph.PostId
    WHERE ph.Level < 5
),
TagStats AS (
    SELECT 
        t.TagName,
        t.Count,
        AVG(p.Score) as AvgScore,
        MAX(p.ViewCount) as MaxViews,
        STRING_AGG(DISTINCT p.OwnerUserId::VARCHAR, ',') as UserOwners
    FROM Tags t
    LEFT JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE t.Count > 100
    GROUP BY t.TagName, t.Count
),
UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.ViewCount,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        MAX(p.CreationDate) as LastPostDate,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Expert'
            WHEN u.Reputation > 5000 THEN 'Advanced'
            WHEN u.Reputation > 1000 THEN 'Intermediate'
            ELSE 'Beginner'
        END as ReputationLevel,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as RankByReputation,
        RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as RankByPostCount,
        DENSE_RANK() OVER (ORDER BY u.ViewCount DESC) as RankByViews
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE u.CreationDate >= '2010-01-01 00:00:00'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.ViewCount, u.UpVotes, u.DownVotes
),
ComplexPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.AcceptedAnswerId,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'Question with Accepted Answer'
            WHEN p.PostTypeId = 1 THEN 'Question without Accepted Answer'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostCategory,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN 
                ARRAY_LENGTH(STRING_TO_ARRAY(p.Tags, '><'), 1)
            ELSE 0
        END as TagCount,
        COALESCE(
            (SELECT AVG(v.Score) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId IN (2,3)),
            0
        ) as AvgVoteScore,
        COALESCE(
            (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (1,2,3,4,5,6)),
            0
        ) as EditCount,
        CASE 
            WHEN p.CreationDate >= '2020-01-01' AND p.CreationDate < '2021-01-01' THEN '2020'
            WHEN p.CreationDate >= '2019-01-01' AND p.CreationDate < '2020-01-01' THEN '2019'
            WHEN p.CreationDate >= '2018-01-01' AND p.CreationDate < '2019-01-01' THEN '2018'
            ELSE 'Older'
        END as PostingYear
    FROM Posts p
    WHERE p.PostTypeId IN (1,2)
),
FinalAnalysis AS (
    SELECT 
        ca.Id,
        ca.PostTypeId,
        ca.ParentId,
        ca.OwnerUserId,
        ca.Score,
        ca.ViewCount,
        ca.Title,
        ca.Tags,
        ca.CreationDate,
        ca.AnswerCount,
        ca.CommentCount,
        ca.FavoriteCount,
        ca.AcceptedAnswerId,
        ca.PostCategory,
        ca.TagCount,
        ca.AvgVoteScore,
        ca.EditCount,
        ca.PostingYear,
        CASE 
            WHEN ca.Score > (SELECT AVG(Score) FROM ComplexPosts) THEN 'Above Average'
            WHEN ca.Score > (SELECT AVG(Score) FROM ComplexPosts) * 0.8 THEN 'Average'
            ELSE 'Below Average'
        END as ScoreClassification,
        CASE 
            WHEN ca.ViewCount > (SELECT AVG(ViewCount) FROM ComplexPosts) THEN 'Popular'
            WHEN ca.ViewCount > (SELECT AVG(ViewCount) FROM ComplexPosts) * 0.5 THEN 'Moderate'
            ELSE 'Rare'
        END as ViewClassification,
        ROW_NUMBER() OVER (PARTITION BY ca.PostTypeId ORDER BY ca.Score DESC) as RankInType,
        DENSE_RANK() OVER (ORDER BY ca.CreationDate DESC) as RecentRank,
        LAG(ca.Score, 1) OVER (ORDER BY ca.CreationDate) as PrevScore,
        LAG(ca.ViewCount, 1) OVER (ORDER BY ca.CreationDate) as PrevViews
    FROM ComplexPosts ca
    WHERE ca.Score > 0
)
SELECT 
    fa.Id,
    fa.PostTypeId,
    fa.ParentId,
    fa.OwnerUserId,
    fa.Score,
    fa.ViewCount,
    fa.Title,
    fa.Tags,
    fa.CreationDate,
    fa.AnswerCount,
    fa.CommentCount,
    fa.FavoriteCount,
    fa.AcceptedAnswerId,
    fa.PostCategory,
    fa.TagCount,
    fa.AvgVoteScore,
    fa.EditCount,
    fa.PostingYear,
    fa.ScoreClassification,
    fa.ViewClassification,
    fa.RankInType,
    fa.RecentRank,
    CASE 
        WHEN fa.PrevScore IS NOT NULL THEN 
            ROUND((fa.Score - fa.PrevScore) * 100.0 / NULLIF(fa.PrevScore, 0), 2)
        ELSE 0
    END as ScoreChangePercentage,
    CASE 
        WHEN fa.PrevViews IS NOT NULL THEN 
            ROUND((fa.ViewCount - fa.PrevViews) * 100.0 / NULLIF(fa.PrevViews, 0), 2)
        ELSE 0
    END as ViewsChangePercentage,
    ua.DisplayName as OwnerName,
    ua.Reputation as OwnerReputation,
    ua.PostCount as OwnerPostCount,
    ua.CommentCount as OwnerCommentCount,
    ua.BadgeCount as OwnerBadgeCount,
    ts.TagName as MostPopularTag,
    ts.Count as TagCount,
    ts.AvgScore as TagAverageScore,
    ph.Path as ParentHierarchy,
    ph.Level as HierarchyLevel,
    CASE 
        WHEN ua.ReputationLevel = 'Expert' AND fa.ScoreClassification = 'Above Average' THEN 'High Performing Expert'
        WHEN ua.ReputationLevel = 'Advanced' AND fa.ScoreClassification = 'Above Average' THEN 'High Performing Advanced'
        WHEN ua.ReputationLevel = 'Intermediate' AND fa.ScoreClassification = 'Above Average' THEN 'High Performing Intermediate'
        ELSE 'Standard Contributor'
    END as PerformanceCategory,
    CASE 
        WHEN fa.EditCount > 10 THEN 'Highly Edited'
        WHEN fa.EditCount > 5 THEN 'Moderately Edited'
        WHEN fa.EditCount > 0 THEN 'Slightly Edited'
        ELSE 'Never Edited'
    END as EditingFrequency,
    COALESCE(ROUND(AVG(fa.Score) OVER (ORDER BY fa.CreationDate ROWS BETWEEN 5 PRECEDING AND CURRENT ROW), 2), 0) as MovingAverageScore,
    COALESCE(ROUND(AVG(fa.ViewCount) OVER (ORDER BY fa.CreationDate ROWS BETWEEN 5 PRECEDING AND CURRENT ROW), 2), 0) as MovingAverageViews
FROM FinalAnalysis fa
LEFT JOIN UserActivity ua ON ua.UserId = fa.OwnerUserId
LEFT JOIN TagStats ts ON ts.TagName = (
    SELECT UNNEST(STRING_TO_ARRAY(fa.Tags, '><'))
    ORDER BY ts.Count DESC
    LIMIT 1
)
LEFT JOIN PostHierarchy ph ON ph.PostId = fa.Id
WHERE 
    (fa.Score > 10 OR fa.ViewCount > 100)
    AND (fa.PostCategory != 'Answer' OR fa.AcceptedAnswerId IS NOT NULL)
    AND fa.CreationDate >= '2015-01-01 00:00:00'
    AND (ua.Reputation >= 1000 OR fa.Score >= 50)
ORDER BY fa.CreationDate DESC, fa.Score DESC
LIMIT 1000;