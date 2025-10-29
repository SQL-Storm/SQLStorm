-- {"query": "7464.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1683} 
WITH RECURSIVE PostHierarchy AS (
    SELECT 
        p.Id as PostId,
        p.ParentId,
        p.PostTypeId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        0 as Level,
        CAST(p.Id AS VARCHAR(1000)) as Path
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.ParentId IS NULL
    
    UNION ALL
    
    SELECT 
        p.Id as PostId,
        p.ParentId,
        p.PostTypeId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        ph.Level + 1,
        CAST(ph.Path || '->' || p.Id AS VARCHAR(1000)) as Path
    FROM Posts p
    INNER JOIN PostHierarchy ph ON p.ParentId = ph.PostId
    WHERE ph.Level < 5
),
UserStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT b.Id) as BadgeCount,
        COUNT(DISTINCT p.Id) as PostCount,
        AVG(p.Score) as AvgPostScore,
        MAX(p.CreationDate) as LastPostDate
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE WHEN t.IsRequired = 1 THEN 'Required' ELSE 'Optional' END as TagType,
        COALESCE(
            (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%'),
            0
        ) as UsageCount
    FROM Tags t
),
ComplexPostAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.ParentId,
        p.PostTypeId,
        p.AnswerCount,
        p.CommentCount,
        p.Tags,
        CASE 
            WHEN p.Score > 100 THEN 'Highly_Voted'
            WHEN p.Score > 50 THEN 'Moderately_Voted'
            WHEN p.Score > 0 THEN 'Slightly_Voted'
            ELSE 'No_Votes'
        END as VotingCategory,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) as ScoreRank,
        NTILE(10) OVER (ORDER BY p.ViewCount DESC) as ViewDecile,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) as RecentPostNumber,
        LAG(p.Score) OVER (ORDER BY p.CreationDate) as PreviousScore,
        LEAD(p.Score) OVER (ORDER BY p.CreationDate) as NextScore,
        AVG(p.Score) OVER (ORDER BY p.CreationDate ROWS BETWEEN 5 PRECEDING AND 5 FOLLOWING) as MovingAvgScore
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) 
)
SELECT 
    COUNT(*) as TotalResults,
    SUM(CASE WHEN cpa.VotingCategory = 'Highly_Voted' THEN 1 ELSE 0 END) as HighlyVotedCount,
    AVG(cpa.Score) as AverageScore,
    MAX(cpa.MovingAvgScore) as MaxMovingAverage,
    MIN(cpa.ViewCount) as MinViews,
    MAX(cpa.AnswerCount) as MaxAnswers,
    COUNT(DISTINCT cpa.OwnerUserId) as DistinctOwners,
    STRING_AGG(DISTINCT u.DisplayName, ', ') as UserNames,
    STRING_AGG(DISTINCT t.TagName, '; ') as Tags,
    COUNT(DISTINCT CASE WHEN ph.Level IS NOT NULL THEN ph.PostId END) as HierarchicalPosts,
    COUNT(DISTINCT CASE WHEN ph.Level IS NULL THEN cp.Id END) as NonHierarchicalPosts,
    AVG(ustats.Reputation) as AvgUserReputation,
    AVG(ustats.AvgPostScore) as AvgUserPostScore,
    COUNT(DISTINCT CASE WHEN b.Id IS NOT NULL THEN b.UserId END) as UsersWithBadges,
    COUNT(DISTINCT CASE WHEN v.Id IS NOT NULL THEN v.UserId END) as UsersWithVotes,
    COALESCE(
        (SELECT COUNT(*) FROM Posts p WHERE p.CreationDate > CURRENT_TIMESTAMP - INTERVAL '7 days'),
        0
    ) as RecentPosts,
    COUNT(DISTINCT CASE WHEN p1.Id IS NOT NULL THEN p1.Id END) as DuplicatePosts,
    STRING_AGG(
        CASE 
            WHEN cpa.PostTypeId = 1 THEN 'Question-' || cpa.Title
            WHEN cpa.PostTypeId = 2 THEN 'Answer-' || cpa.Title
            ELSE 'Other-' || cpa.Title 
        END, 
        ' | '
    ) as SamplePostTitles,
    SUM(CASE WHEN cpa.AnswerCount > 0 THEN 1 ELSE 0 END) as QuestionsWithAnswers,
    AVG(CASE WHEN cpa.Score IS NOT NULL THEN cpa.Score ELSE 0 END) as AvgScoreWithNulls,
    COUNT(CASE WHEN cpa.Tags IS NOT NULL AND LENGTH(cpa.Tags) > 0 THEN 1 END) as PostsHavingTags,
    COUNT(*) FILTER (WHERE cpa.MovingAvgScore > (SELECT AVG(MovingAvgScore) FROM ComplexPostAnalysis)) as AboveAverageMovingAvg,
    COUNT(*) FILTER (WHERE cpa.Score > (SELECT AVG(Score) FROM ComplexPostAnalysis)) as AboveAverageScore,
    (SELECT COUNT(*) FROM Badges b WHERE b.Class = 1) as GoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.Class = 2) as SilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.Class = 3) as BronzeBadges,
    STRING_AGG(DISTINCT CASE WHEN LENGTH(u.WebsiteUrl) > 0 THEN LEFT(u.WebsiteUrl, 20) ELSE 'No Website' END, ' | ') as WebsiteSample
FROM ComplexPostAnalysis cpa
LEFT JOIN Posts p1 ON p1.Id = cpa.ParentId
LEFT JOIN Users u ON u.Id = cpa.OwnerUserId
LEFT JOIN UserStats ustats ON ustats.UserId = u.Id
LEFT JOIN Badges b ON b.UserId = u.Id
LEFT JOIN Votes v ON v.UserId = u.Id
LEFT JOIN PostHierarchy ph ON ph.PostId = cpa.PostId
LEFT JOIN Tags t ON t.TagName IN (
    SELECT TRIM(SUBSTRING(cpa.Tags, n.start, n.length)) 
    FROM (
        SELECT 1 as start, 1 as length
        UNION ALL
        SELECT 2, 1
        UNION ALL
        SELECT 3, 1
        UNION ALL
        SELECT 4, 1
        UNION ALL
        SELECT 5, 1
    ) n
    WHERE n.start < LENGTH(cpa.Tags) AND SUBSTRING(cpa.Tags, n.start, 1) = '<'
    OFFSET 1
    LIMIT 5
)
WHERE cpa.CreationDate > CURRENT_TIMESTAMP - INTERVAL '30 days'
GROUP BY 
    cpa.PostTypeId,
    ustats.Reputation,
    ustats.AvgPostScore,
    ustats.PostCount,
    ustats.BadgeCount,
    t.TagName,
    ph.Level
HAVING 
    COUNT(*) > 0
    AND AVG(cpa.Score) > 0
    AND COUNT(DISTINCT u.Id) > 0
ORDER BY 
    AVG(cpa.Score) DESC,
    COUNT(DISTINCT u.Id) DESC,
    SUM(cpa.ViewCount) DESC
LIMIT 1000;