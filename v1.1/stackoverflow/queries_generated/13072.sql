-- {"query": "13072.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 920} 

WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS rn,
        COUNT(ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (5, 6)) OVER (PARTITION BY p.Id) AS EditCount,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) OVER (PARTITION BY p.Id) AS LastClosedDate
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE p.PostTypeId = 1 AND p.ClosedDate IS NULL
),
TopUserPosts AS (
    SELECT 
        rp.Id,
        rp.OwnerUserId,
        rp.Score,
        rp.ViewCount,
        rp.CreationDate,
        rp.EditCount,
        rp.LastClosedDate,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS Upvotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS Downvotes
    FROM RankedPosts rp
    LEFT JOIN Votes v ON rp.Id = v.PostId
    WHERE rp.rn <= 5
    GROUP BY rp.Id, rp.OwnerUserId, rp.Score, rp.ViewCount, rp.CreationDate, rp.EditCount, rp.LastClosedDate
),
FinalUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Location,
        SUM(tup.Score) AS TotalScore,
        AVG(tup.ViewCount) AS AvgViewCount,
        SUM(tup.EditCount) AS TotalEdits,
        SUM(tup.Upvotes) AS TotalUpvotes,
        SUM(tup.Downvotes) AS TotalDownvotes,
        COUNT(DISTINCT CASE WHEN tup.LastClosedDate IS NOT NULL THEN tup.Id END) AS ReopenedPosts
    FROM Users u
    JOIN TopUserPosts tup ON u.Id = tup.OwnerUserId
    WHERE u.Views > 1000 AND u.CreationDate > '2010-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
    HAVING COUNT(DISTINCT tup.Id) >= 3
),
BadgeMetrics AS (
    SELECT
        UserId,
        COUNT(*) FILTER (WHERE Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE Class = 3) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
)
SELECT 
    fu.UserId,
    fu.DisplayName,
    fu.Reputation,
    fu.Location,
    fu.TotalScore,
    fu.AvgViewCount,
    bm.GoldBadges,
    bm.SilverBadges,
    bm.BronzeBadges,
    COALESCE(bm.GoldBadges * 3 + bm.SilverBadges * 2 + bm.BronzeBadges, 0) AS WeightedBadges,
    fu.TotalEdits,
    fu.TotalUpvotes,
    fu.TotalDownvotes,
    fu.ReopenedPosts,
    DENSE_RANK() OVER (ORDER BY fu.TotalScore DESC, fu.Reputation DESC, bm.GoldBadges DESC) AS PerformanceRank
FROM FinalUsers fu
LEFT JOIN BadgeMetrics bm ON fu.UserId = bm.UserId
WHERE fu.DisplayName NOT LIKE '%[Bot]%'
ORDER BY PerformanceRank;
