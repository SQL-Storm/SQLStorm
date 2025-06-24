
WITH RecentPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        COALESCE(CAST(NULLIF(p.OwnerUserId, -1) AS SIGNED), -1) AS ActualOwnerUserId,
        GROUP_CONCAT(t.TagName) AS TagsArray
    FROM Posts p
    LEFT JOIN Tags t ON LOCATE(t.TagName, p.Tags) > 0 
    WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS DATETIME) - INTERVAL 1 MONTH
    GROUP BY p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.OwnerUserId
),
VoteStatistics AS (
    SELECT 
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId IN (2, 1) THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        COUNT(v.Id) AS TotalVotes
    FROM Votes v
    GROUP BY v.PostId
),
UserReputation AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        @rank := @rank + 1 AS ReputationRank
    FROM Users u, (SELECT @rank := 0) r
    ORDER BY u.Reputation DESC
),
BadgeCounts AS (
    SELECT 
        b.UserId,
        COUNT(b.Id) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
PostHistoryDetails AS (
    SELECT 
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.UserId,
        MAX(ph.CreationDate) AS LastModifiedDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (5, 11, 12, 14)
    GROUP BY ph.PostId, ph.PostHistoryTypeId, ph.UserId
)

SELECT 
    rp.PostId,
    rp.Title,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    COALESCE(u.DisplayName, 'Anonymous') AS OwnerDisplayName,
    COALESCE(vs.UpVotes, 0) AS UpVotes,
    COALESCE(vs.DownVotes, 0) AS DownVotes,
    u.Reputation,
    bc.TotalBadges,
    ph.LastModifiedDate,
    CASE 
        WHEN ph.PostHistoryTypeId = 10 THEN 'Closed' 
        WHEN ph.PostHistoryTypeId = 11 THEN 'Reopened' 
        ELSE 'Open' 
    END AS PostStatus,
    TagsArray AS Tags
FROM RecentPosts rp
LEFT JOIN Users u ON u.Id = rp.ActualOwnerUserId
LEFT JOIN VoteStatistics vs ON vs.PostId = rp.PostId
LEFT JOIN BadgeCounts bc ON bc.UserId = u.Id
LEFT JOIN PostHistoryDetails ph ON ph.PostId = rp.PostId
WHERE rp.ViewCount > (
    SELECT AVG(ViewCount) FROM RecentPosts
) 
ORDER BY rp.CreationDate DESC
LIMIT 50;
