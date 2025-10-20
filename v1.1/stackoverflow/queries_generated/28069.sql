-- {"query": "28069.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1722} 

WITH UserStats AS (
    SELECT 
        u.Id,
        u.Reputation,
        u.CreationDate,
        COALESCE(u.DisplayName, 'Anonymous') AS DisplayName,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        AVG(p.Score) OVER (PARTITION BY u.Id) AS AvgPostScore,
        RANK() OVER (ORDER BY u.Reputation DESC) AS GlobalRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id
),
PostAnalysis AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.ClosedDate,
        u.GlobalRank,
        STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><') AS TagArray,
        (SELECT MAX(CreationDate) FROM Posts p2 WHERE p2.OwnerUserId = p.OwnerUserId) AS LastUserPostDate,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevPostScore,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'CommunityWiki'
            ELSE 'Active'
        END AS PostStatus
    FROM Posts p
    INNER JOIN UserStats u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
),
TagExplosion AS (
    SELECT 
        pa.Id AS PostId,
        UNNEST(pa.TagArray) AS Tag,
        ph.CreationDate AS LastEditDate,
        COALESCE(ph.UserDisplayName, 'System') AS LastEditor,
        ROW_NUMBER() OVER (PARTITION BY pa.Id ORDER BY ph.CreationDate DESC) AS EditRank
    FROM PostAnalysis pa
    LEFT JOIN PostHistory ph ON pa.Id = ph.PostId AND ph.PostHistoryTypeId IN (4,5,6)
)
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.GlobalRank,
    u.GoldBadges,
    u.SilverBadges,
    u.BronzeBadges,
    pa.PostId,
    pa.PostStatus,
    pa.Score AS PostScore,
    pa.ViewCount,
    pa.LastUserPostDate,
    te.Tag AS MostRecentTag,
    te.LastEditor,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = pa.Id AND v.VoteTypeId = 2) AS Upvotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = pa.Id AND v.VoteTypeId = 3) AS Downvotes,
    COALESCE(SUM(ph.Text ~ 'migration')::INT, 0) AS MigrationEdits
FROM UserStats u
INNER JOIN PostAnalysis pa ON u.Id = pa.OwnerUserId
LEFT JOIN TagExplosion te ON pa.Id = te.PostId AND te.EditRank = 1
LEFT JOIN PostHistory ph ON pa.Id = ph.PostId AND ph.PostHistoryTypeId = 35
WHERE u.Reputation > 10000
    AND (pa.Score > 100 OR pa.ViewCount > 1000)
    AND (u.UpVotes - u.DownVotes) > 50
GROUP BY 
    u.Id, 
    u.DisplayName, 
    u.GlobalRank, 
    u.GoldBadges, 
    u.SilverBadges, 
    u.BronzeBadges, 
    pa.PostId, 
    pa.PostStatus, 
    pa.Score, 
    pa.ViewCount, 
    pa.LastUserPostDate, 
    te.Tag, 
    te.LastEditor
HAVING COUNT(DISTINCT te.Tag) > 3
UNION ALL
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.GlobalRank,
    u.GoldBadges,
    u.SilverBadges,
    u.BronzeBadges,
    NULL AS PostId,
    'Inactive' AS PostStatus,
    NULL AS PostScore,
    NULL AS ViewCount,
    NULL AS LastUserPostDate,
    NULL AS MostRecentTag,
    NULL AS LastEditor,
    NULL AS Upvotes,
    NULL AS Downvotes,
    0 AS MigrationEdits
FROM UserStats u
WHERE NOT EXISTS (SELECT 1 FROM PostAnalysis pa WHERE pa.OwnerUserId = u.Id)
ORDER BY GlobalRank ASC, PostScore DESC NULLS LAST;
