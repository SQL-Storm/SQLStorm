-- {"query": "776.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1587} 

WITH RecursiveTagHierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        1 AS Depth
    FROM Tags t
    WHERE t.IsRequired = 1

    UNION ALL

    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        r.Depth + 1
    FROM Tags t
    INNER JOIN PostLinks pl ON pl.PostId = t.ExcerptPostId
    INNER JOIN RecursiveTagHierarchy r ON pl.RelatedPostId = r.ExcerptPostId
    WHERE r.Depth < 3
),
UserBadgesRanked AS (
    SELECT 
        b.UserId,
        b.Name AS BadgeName,
        b.Class,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Class, b.Date DESC) AS rn
    FROM Badges b
    WHERE b.Class IN (1,2,3)
),
TopUserBadges AS (
    SELECT UserId, BadgeName, Class
    FROM UserBadgesRanked
    WHERE rn = 1
),
TopActiveUsers AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COALESCE(tub.BadgeName, 'No Badge') AS TopBadge,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        SUM(COALESCE(p.Score,0)) AS TotalPostScore,
        AVG(COALESCE(p.Score,0)) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN TopUserBadges tub ON tub.UserId = u.Id
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location, u.Views, u.UpVotes, u.DownVotes, tub.BadgeName
),
PostScoreRanks AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        u.DisplayName AS OwnerName,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS ScoreRank,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS RecentRank,
        COUNT(*) OVER (PARTITION BY p.PostTypeId) AS TotalPostsOfType
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId IN (1,2)
),
CorrelatedCommentsCount AS (
    SELECT 
        p.Id AS PostId,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.CreationDate >= p.CreationDate - INTERVAL '30 days') AS RecentCommentsCount,
        (SELECT AVG(c.Score) FROM Comments c WHERE c.PostId = p.Id) AS AvgCommentScore
    FROM Posts p
    WHERE p.PostTypeId = 1
),
FinalFilteredPosts AS (
    SELECT
        psr.Id,
        psr.PostTypeId,
        psr.Title,
        psr.Tags,
        psr.CreationDate,
        psr.Score,
        psr.ViewCount,
        psr.OwnerUserId,
        psr.OwnerName,
        psr.ScoreRank,
        psr.RecentRank,
        psr.TotalPostsOfType,
        ccc.RecentCommentsCount,
        ccc.AvgCommentScore,
        COALESCE(u.Reputation, 0) AS OwnerReputation,
        COALESCE(u.Views, 0) AS OwnerViews,
        COALESCE(u.TopBadge, 'None') AS OwnerTopBadge
    FROM PostScoreRanks psr
    LEFT JOIN CorrelatedCommentsCount ccc ON ccc.PostId = psr.Id
    LEFT JOIN Users u ON u.Id = psr.OwnerUserId
    WHERE psr.ScoreRank <= 100
      AND (ccc.RecentCommentsCount > 5 OR ccc.RecentCommentsCount IS NULL)
      AND (psr.Tags IS NOT NULL AND psr.Tags <> '')
),
AggregatedTagStats AS (
    SELECT 
        unnest(string_to_array(substring(Tags, 2, length(Tags) - 2), '><')) AS Tag,
        COUNT(*) AS PostCount,
        AVG(Score) AS AvgScore,
        SUM(ViewCount) AS TotalViews
    FROM FinalFilteredPosts
    GROUP BY Tag
),
CombinedResults AS (
    SELECT 
        f.Id,
        f.PostTypeId,
        f.Title,
        f.Tags,
        f.CreationDate,
        f.Score,
        f.ViewCount,
        f.OwnerUserId,
        f.OwnerName,
        f.ScoreRank,
        f.RecentRank,
        f.TotalPostsOfType,
        f.RecentCommentsCount,
        f.AvgCommentScore,
        f.OwnerReputation,
        f.OwnerViews,
        f.OwnerTopBadge,
        ats.PostCount,
        ats.AvgScore AS TagAvgScore,
        ats.TotalViews AS TagTotalViews
    FROM FinalFilteredPosts f
    LEFT JOIN AggregatedTagStats ats ON ats.Tag = ANY(string_to_array(substring(f.Tags, 2, length(f.Tags) - 2), '><'))
)
SELECT DISTINCT ON (c.Id)
    c.Id AS PostId,
    c.PostTypeId,
    c.Title,
    c.CreationDate,
    c.Score,
    c.ViewCount,
    c.OwnerUserId,
    c.OwnerName,
    c.OwnerReputation,
    c.OwnerViews,
    c.OwnerTopBadge,
    c.ScoreRank,
    c.RecentRank,
    c.TotalPostsOfType,
    c.RecentCommentsCount,
    c.AvgCommentScore,
    STRING_AGG(DISTINCT rh.TagName, ', ') OVER (PARTITION BY c.Id ORDER BY rh.Depth DESC ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS RelatedTags,
    MAX(rh.Depth) OVER (PARTITION BY c.Id) AS MaxTagHierarchyDepth,
    c.PostCount,
    c.TagAvgScore,
    c.TagTotalViews,
    CASE 
        WHEN c.Score > 100 THEN 'High Score'
        WHEN c.Score BETWEEN 50 AND 100 THEN 'Medium Score'
        ELSE 'Low Score'
    END AS ScoreCategory,
    CASE 
        WHEN c.ViewCount > 10000 THEN 'Popular'
        ELSE 'Less Popular'
    END AS PopularityCategory
FROM CombinedResults c
LEFT JOIN LATERAL (
    SELECT DISTINCT rh.TagName, rh.Depth
    FROM RecursiveTagHierarchy rh
    WHERE rh.TagName = ANY(string_to_array(substring(c.Tags, 2, length(c.Tags) - 2), '><'))
    ORDER BY rh.Depth DESC
    LIMIT 5
) rh ON TRUE
ORDER BY c.Score DESC, c.ViewCount DESC, c.CreationDate DESC
LIMIT 200;
