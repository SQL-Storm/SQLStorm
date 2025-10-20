-- {"query": "28008.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1608} 

WITH ActiveUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id) AS PostCount,
        (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) AS CommentCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id) AS VoteCount
    FROM Users u
    WHERE u.Reputation > 10000
),
RecentBadges AS (
    SELECT 
        b.UserId,
        b.Name AS LatestBadge,
        b.Date,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) AS rn
    FROM Badges b
    INNER JOIN ActiveUsers au ON b.UserId = au.UserId
),
PostMetrics AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        ph.CreationDate AS LastEditDate,
        COALESCE(ph.UserDisplayName, u.DisplayName) AS LastEditor,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
        ROUND(1.0 * SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) / NULLIF(SUM(CASE WHEN v.VoteTypeId IN (2,3) THEN 1 ELSE 0 END), 0), 2) AS VoteRatio
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 5
    LEFT JOIN Users u ON ph.UserId = u.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.OwnerUserId, p.Score, p.ViewCount, ph.CreationDate, ph.UserDisplayName, u.DisplayName
),
TagAnalysis AS (
    SELECT 
        SPLIT_PART(REPLACE(REPLACE(p.Tags, '><', ','), '<>', ''), ',', n) AS Tag,
        COUNT(*) AS TagCount,
        AVG(pm.VoteRatio) AS AvgVoteRatio
    FROM Posts p
    JOIN PostMetrics pm ON p.Id = pm.PostId
    CROSS JOIN GENERATE_SERIES(1, 5) n
    WHERE p.Tags IS NOT NULL AND LENGTH(p.Tags) > 0
    GROUP BY Tag
    HAVING COUNT(*) > 100
)
SELECT 
    au.UserId,
    au.DisplayName,
    au.Reputation,
    rb.LatestBadge,
    pm.PostId,
    pm.VoteRatio,
    pm.Upvotes,
    pm.Downvotes,
    ARRAY_AGG(DISTINCT ta.Tag) AS TopTags,
    RANK() OVER (ORDER BY pm.VoteRatio DESC) AS VoteRank,
    CASE 
        WHEN EXISTS (SELECT 1 FROM Posts p2 WHERE p2.OwnerUserId = au.UserId AND p2.Score > 100) 
        THEN 'HighQualityContributor' 
        ELSE 'RegularContributor' 
    END AS ContributorType
FROM ActiveUsers au
JOIN RecentBadges rb ON au.UserId = rb.UserId AND rb.rn = 1
JOIN PostMetrics pm ON au.UserId = pm.OwnerUserId
LEFT JOIN TagAnalysis ta ON pm.PostId IN (SELECT Id FROM Posts WHERE Tags LIKE '%' || ta.Tag || '%')
WHERE pm.VoteRatio > 0.7
  AND pm.CommentCount > 5
  AND (pm.Upvotes - pm.Downvotes) > 10
GROUP BY au.UserId, au.DisplayName, au.Reputation, rb.LatestBadge, pm.PostId, pm.VoteRatio, pm.Upvotes, pm.Downvotes
HAVING COUNT(ta.Tag) > 2
UNION ALL
SELECT 
    NULL AS UserId,
    'CommunityWiki' AS DisplayName,
    NULL AS Reputation,
    NULL AS LatestBadge,
    p.Id AS PostId,
    1.0 AS VoteRatio,
    0 AS Upvotes,
    0 AS Downvotes,
    ARRAY['Wiki'] AS TopTags,
    0 AS VoteRank,
    'System' AS ContributorType
FROM Posts p
WHERE p.CommunityOwnedDate IS NOT NULL
ORDER BY VoteRank ASC, Reputation DESC
LIMIT 1000;
