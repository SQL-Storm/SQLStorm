-- {"query": "5004.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1154} 
WITH RecentActiveUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC, COUNT(DISTINCT c.Id) DESC) AS rn
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.CreationDate > (NOW() - INTERVAL '90 days')
    LEFT JOIN Comments c ON c.UserId = u.Id AND c.CreationDate > (NOW() - INTERVAL '90 days')
    WHERE u.LastAccessDate > (NOW() - INTERVAL '30 days')
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
TopUsers AS (
    SELECT * FROM RecentActiveUsers WHERE rn <= 50
),
UserPostRanks AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS ScoreRank
    FROM Posts p
    WHERE p.OwnerUserId IN (SELECT UserId FROM TopUsers)
),
PostEditCounts AS (
    SELECT 
        ph.PostId,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) AS EditCount,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 10) AS CloseVoteCount,
        MAX(ph.CreationDate) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) AS LastEditDate
    FROM PostHistory ph
    WHERE ph.PostId IS NOT NULL
    GROUP BY ph.PostId
),
PostVotes AS (
    SELECT
        v.PostId,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpVoteCount,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownVoteCount,
        COALESCE(SUM(v.BountyAmount), 0) AS TotalBounty
    FROM Votes v
    WHERE v.PostId IS NOT NULL
    GROUP BY v.PostId
),
LatestBadge AS (
    SELECT
        b.UserId,
        b.Name AS BadgeName,
        b.Date AS BadgeDate,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC, b.Class ASC) AS rn
    FROM Badges b
)
SELECT 
    u.UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreation,
    COALESCE(u.TotalPosts,0) AS PostsLast90d,
    COALESCE(u.TotalComments,0) AS CommentsLast90d,
    lb.BadgeName AS LatestBadge,
    lb.BadgeDate AS LatestBadgeDate,
    p.PostId,
    COALESCE(pt.Name, 'Unknown') AS PostType,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate AS PostCreation,
    pe.EditCount,
    pe.LastEditDate,
    pe.CloseVoteCount,
    pv.UpVoteCount,
    pv.DownVoteCount,
    pv.TotalBounty,
    CASE 
        WHEN pe.EditCount > 5 THEN 'Highly Edited'
        WHEN pe.EditCount > 0 THEN 'Edited'
        ELSE 'Never Edited'
    END AS EditStatus,
    CASE 
        WHEN pv.DownVoteCount IS NULL OR pv.DownVoteCount = 0 THEN NULL
        ELSE ROUND(pv.UpVoteCount::numeric / NULLIF(pv.DownVoteCount,0),2)
    END AS UpDownRatio,
    CASE 
        WHEN p.Score > 10 AND pv.UpVoteCount > 20 THEN 'Very Popular'
        WHEN p.Score < 0 THEN 'Controversial'
        ELSE 'Normal'
    END AS PopularityLevel,
    tlist.Tags
FROM TopUsers u
LEFT JOIN LatestBadge lb ON lb.UserId = u.UserId AND lb.rn = 1
LEFT JOIN UserPostRanks p ON p.OwnerUserId = u.UserId AND p.ScoreRank <= 3
LEFT JOIN PostTypes pt ON pt.Id = p.PostTypeId
LEFT JOIN PostEditCounts pe ON pe.PostId = p.PostId
LEFT JOIN PostVotes pv ON pv.PostId = p.PostId
LEFT JOIN (
    SELECT 
        p2.Id AS PostId,
        STRING_AGG(tag.TagName, ', ') AS Tags
    FROM Posts p2
    JOIN LATERAL (
        SELECT unnest(string_to_array(substring(p2.Tags, 2, length(p2.Tags)-2), '><')) AS TagName
    ) tag ON TRUE
    GROUP BY p2.Id
) tlist ON tlist.PostId = p.PostId
WHERE 
    (pv.UpVoteCount IS NULL OR pv.UpVoteCount > 5)
    AND (pe.EditCount IS NULL OR pe.EditCount = 0 OR pe.EditCount > 2)
    AND (tlist.Tags IS NULL OR position('sql' in lower(tlist.Tags)) = 0)
ORDER BY 
    u.Reputation DESC,
    p.Score DESC NULLS LAST,
    p.ViewCount DESC NULLS LAST,
    p.CreationDate DESC NULLS LAST;