-- {"query": "13062.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 728} 

WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS PostRank,
        DENSE_RANK() OVER (ORDER BY p.ViewCount DESC NULLS LAST) AS ViewDensityRank,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AvgUserScore,
        SUM(p.CommentCount) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS CumulativeComments
    FROM Posts p
    WHERE p.PostTypeId = 1
),
UserBadges AS (
    SELECT
        u.Id AS UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id
),
TopContributors AS (
    SELECT 
        rp.OwnerUserId,
        COUNT(DISTINCT rp.Id) AS NumPosts,
        SUM(rp.Score) AS TotalScore,
        AVG(rp.AvgUserScore) AS AvgScore,
        MAX(rp.ViewDensityRank) AS MaxViewDensityRank,
        ARRAY_AGG(DISTINCT CONCAT(u.DisplayName, ': ', rp.Id::text) ORDER BY rp.Score DESC) AS TopPostDetails
    FROM RankedPosts rp
    JOIN Users u ON rp.OwnerUserId = u.Id
    WHERE rp.PostRank <= 5
    GROUP BY rp.OwnerUserId
    HAVING SUM(rp.Score) > 1000
),
EditedPosts AS (
    SELECT 
        ph.PostId,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId BETWEEN 4 AND 6) AS EditCount,
        MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    GROUP BY ph.PostId
)
SELECT 
    tc.OwnerUserId,
    u.DisplayName,
    tc.NumPosts,
    tc.TotalScore,
    tc.AvgScore,
    tc.MaxViewDensityRank,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ep.EditCount,
    ep.LastEditDate,
    tc.TopPostDetails
FROM TopContributors tc
JOIN Users u ON tc.OwnerUserId = u.Id
LEFT JOIN UserBadges ub ON tc.OwnerUserId = ub.UserId
LEFT JOIN EditedPosts ep ON tc.OwnerUserId = ep.PostId
WHERE u.Reputation > 5000 AND u.Location IS NOT NULL
ORDER BY tc.TotalScore DESC, u.Reputation DESC
LIMIT 10;
