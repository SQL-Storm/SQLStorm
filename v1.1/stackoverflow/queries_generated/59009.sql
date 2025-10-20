-- {"query": "59009.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2061, "output_tokens": 1292} 
WITH RECURSIVE PostHierarchy AS (
    SELECT 
        p.Id,
        p.ParentId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        0 as Depth,
        CAST(p.Id AS VARCHAR(1000)) as Path
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.ParentId IS NULL
    
    UNION ALL
    
    SELECT 
        p.Id,
        p.ParentId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        ph.Depth + 1,
        CAST(ph.Path || ',' || p.Id AS VARCHAR(1000))
    FROM Posts p
    INNER JOIN PostHierarchy ph ON p.ParentId = ph.Id
    WHERE ph.Depth < 5
),
UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT c.Id) as TotalComments,
        COUNT(DISTINCT b.Id) as TotalBadges,
        COUNT(DISTINCT v.Id) as TotalVotes,
        AVG(p.Score) as AvgPostScore,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        MAX(b.Date) as LastBadgeDate,
        MAX(v.CreationDate) as LastVoteDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TagPerformance AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        AVG(p.Score) as AvgScore,
        SUM(p.ViewCount) as TotalViews,
        COUNT(DISTINCT p.Id) as PostCount,
        STRING_AGG(DISTINCT u.DisplayName, ', ') as PostOwners
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName, t.Count
    HAVING COUNT(DISTINCT p.Id) > 100
),
ComplexQueryResults AS (
    SELECT 
        ph.Id,
        ph.ParentId,
        ph.Score,
        ph.ViewCount,
        ph.OwnerUserId,
        ph.Depth,
        ph.Path,
        uas.DisplayName as OwnerDisplayName,
        uas.Reputation as OwnerReputation,
        uas.TotalPosts as OwnerTotalPosts,
        uas.AvgPostScore as OwnerAvgPostScore,
        uas.LastPostDate as OwnerLastPostDate,
        tp.TagName,
        tp.TagCount,
        tp.AvgScore as TagAvgScore,
        tp.TotalViews as TagTotalViews,
        tp.PostCount as TagPostCount,
        tp.PostOwners,
        p.Title,
        p.Body,
        p.CreationDate,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.Tags,
        p.ContentLicense,
        pv.VoteType,
        pv.VoteCount
    FROM PostHierarchy ph
    LEFT JOIN UserActivityStats uas ON ph.OwnerUserId = uas.UserId
    LEFT JOIN (
        SELECT 
            p.Id as PostId,
            t.TagName,
            t.Count as TagCount,
            AVG(p.Score) as AvgScore,
            SUM(p.ViewCount) as TotalViews,
            COUNT(DISTINCT p.Id) as PostCount,
            STRING_AGG(DISTINCT u.DisplayName, ', ') as PostOwners
        FROM Posts p
        INNER JOIN Tags t ON p.Tags LIKE '%' || t.TagName || '%'
        LEFT JOIN Users u ON p.OwnerUserId = u.Id
        WHERE p.PostTypeId = 1
        GROUP BY p.Id, t.TagName, t.Count
    ) tp ON ph.Id = tp.PostId
    LEFT JOIN Posts p ON ph.Id = p.Id
    LEFT JOIN (
        SELECT 
            v.PostId,
            vt.Name as VoteType,
            COUNT(v.Id) as VoteCount
        FROM Votes v
        INNER JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
        WHERE vt.Id IN (1, 2, 3, 5) -- Only consider specific vote types
        GROUP BY v.PostId, vt.Name
    ) pv ON ph.Id = pv.PostId
    WHERE ph.Depth <= 3
    AND uas.Reputation > 1000
    AND (tp.TagCount > 50 OR tp.TagName IS NULL)
)
SELECT 
    COUNT(*) as TotalResults,
    COUNT(DISTINCT Id) as UniquePosts,
    COUNT(DISTINCT OwnerUserId) as UniqueOwners,
    COUNT(DISTINCT TagName) as UniqueTags,
    AVG(Score) as AvgScore,
    AVG(ViewCount) as AvgViews,
    AVG(OwnerReputation) as AvgOwnerReputation,
    MAX(OwnerTotalPosts) as MaxOwnerPosts,
    MAX(OwnerAvgPostScore) as MaxOwnerAvgScore,
    COUNT(DISTINCT CASE WHEN VoteType = 'UpMod' THEN PostId END) as UpVoteCount,
    COUNT(DISTINCT CASE WHEN VoteType = 'DownMod' THEN PostId END) as DownVoteCount,
    COUNT(DISTINCT CASE WHEN VoteType = 'Favorite' THEN PostId END) as FavoriteCount,
    STRING_AGG(DISTINCT OwnerDisplayName, ', ') as AllOwners,
    STRING_AGG(DISTINCT TagName, '; ') as AllTags
FROM ComplexQueryResults
GROUP BY 
    CASE WHEN COUNT(*) > 1000 THEN 1 ELSE 0 END
HAVING COUNT(*) >= 100
ORDER BY MAX(OwnerReputation) DESC
LIMIT 1000;