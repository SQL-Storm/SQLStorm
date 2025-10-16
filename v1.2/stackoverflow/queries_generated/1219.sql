-- {"query": "1219.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1168} 

WITH RecursiveTagHierarchy AS (
    SELECT 
        t.Id, 
        t.TagName, 
        t.Count,
        CAST(t.TagName AS VARCHAR(350)) AS FullPath,
        1 AS Level
    FROM Tags t
    WHERE t.IsModeratorOnly = 0

    UNION ALL

    SELECT 
        c.Id, 
        c.TagName, 
        c.Count,
        CAST(CONCAT(p.FullPath, ' > ', c.TagName) AS VARCHAR(350)),
        p.Level + 1
    FROM Tags c
    JOIN Tags p ON c.Id != p.Id AND c.Count <= p.Count
    JOIN RecursiveTagHierarchy rth ON p.Id = rth.Id
    WHERE c.IsRequired = 1 AND rth.Level < 2
), RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        COALESCE(u.DisplayName, 'Anonymous') AS OwnerName,
        COALESCE(p.Tags, '') AS Tags,
        ROW_NUMBER() OVER (
            PARTITION BY p.OwnerUserId 
            ORDER BY p.CreationDate DESC, p.Score DESC
        ) AS RecentPostRank,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) AS TotalPostsByUser
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2) AND p.CreationDate > '2019-01-01'
), UserBadgeCounts AS (
    SELECT
        b.UserId,
        b.Class,
        COUNT(DISTINCT b.Id) AS BadgeCount
    FROM Badges b
    GROUP BY b.UserId, b.Class
), UserAggregateBadges AS (
    SELECT
        ubc.UserId,
        MAX(CASE WHEN ubc.Class = 1 THEN ubc.BadgeCount ELSE 0 END) AS GoldBadges,
        MAX(CASE WHEN ubc.Class = 2 THEN ubc.BadgeCount ELSE 0 END) AS SilverBadges,
        MAX(CASE WHEN ubc.Class = 3 THEN ubc.BadgeCount ELSE 0 END) AS BronzeBadges
    FROM UserBadgeCounts ubc
    GROUP BY ubc.UserId
), CloseReasonCounts AS (
    SELECT
        cht.Name AS Reason,
        COUNT(ph.Id) AS CloseCount
    FROM PostHistory ph
    INNER JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    LEFT JOIN CloseReasonTypes cht ON TRY_CAST(ph.Comment AS INT) = cht.Id
    WHERE ph.PostHistoryTypeId = 10 -- Post Closed
    GROUP BY cht.Name
), TopUsersByReputation AS (
    SELECT 
        u.Id, u.DisplayName, u.Reputation,
        COALESCE(ub.GoldBadges,0) AS GoldBadges,
        COALESCE(ub.SilverBadges,0) AS SilverBadges,
        COALESCE(ub.BronzeBadges,0) AS BronzeBadges,
        u.CreationDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RankByRep
    FROM Users u
    LEFT JOIN UserAggregateBadges ub ON ub.UserId = u.Id
    WHERE u.Reputation > 1000
)
SELECT
    tth.FullPath AS TagHierPath,
    rp.PostId,
    rp.PostTypeId,
    CASE 
        WHEN rp.PostTypeId = 1 THEN 
            CONCAT(LEFT(rp.Title, 100), CASE WHEN LENGTH(rp.Title) > 100 THEN '...' ELSE '' END)
        ELSE 'Answer to: ' || 
            (SELECT LEFT(q.Title, 50) || CASE WHEN LENGTH(q.Title) > 50 THEN '...' ELSE '' END 
             FROM Posts q WHERE q.Id = rp.ParentId)
    END AS PostSummary,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.OwnerName,
    rp.Tags,
    rp.RecentPostRank,
    rp.TotalPostsByUser,
    COALESCE(ub.GoldBadges, 0) AS OwnerGoldBadges,
    COALESCE(ub.SilverBadges, 0) AS OwnerSilverBadges,
    COALESCE(ub.BronzeBadges, 0) AS OwnerBronzeBadges,
    crc.CloseCount,
    tth.Level AS TagLevel,
    ROW_NUMBER() OVER (PARTITION BY rp.OwnerName ORDER BY rp.Score DESC) AS ScoreRankWithinUser,
    CASE 
        WHEN rp.ViewCount > 10000 THEN 'Hot'
        WHEN rp.ViewCount BETWEEN 1000 AND 10000 THEN 'Trending'
        ELSE 'Normal'
    END AS PopularityCategory,
    RPAD(SUBSTRING(rp.OwnerName FROM 1 FOR 5), 10, '-') AS ShortOwnerNamePadded
FROM RankedPosts rp
LEFT JOIN UserAggregateBadges ub ON ub.UserId = (
    SELECT DISTINCT OwnerUserId FROM Posts WHERE Id = rp.PostId
)
LEFT JOIN CloseReasonCounts crc ON TRUE -- join to give a cross join effect for aggregation
LEFT JOIN RecursiveTagHierarchy tth ON rp.Tags LIKE CONCAT('%', tth.TagName, '%')
WHERE 
    rp.RecentPostRank <= 3
    AND (rp.Score > 5 OR rp.ViewCount > 500)
ORDER BY
    rp.OwnerName ASC,
    ScoreRankWithinUser ASC
LIMIT 100;
