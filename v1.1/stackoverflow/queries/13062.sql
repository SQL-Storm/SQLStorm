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
        DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) AS ViewDensityRank,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AvgUserScore,
        SUM(p.CommentCount) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeComments
    FROM Posts p
    WHERE p.PostTypeId = 1
),
UserBadges AS (
    SELECT
        u.Id AS UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
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
        -- build a concatenated list of distinct top post details in a dialect-agnostic way
        STRING_AGG(DISTINCT (u.DisplayName || ': ' || CAST(rp.Id AS VARCHAR)), ', ') AS TopPostDetails
    FROM RankedPosts rp
    JOIN Users u ON rp.OwnerUserId = u.Id
    WHERE rp.PostRank <= 5
    GROUP BY rp.OwnerUserId, u.DisplayName
    HAVING SUM(rp.Score) > 1000
),
EditedPosts AS (
    SELECT 
        ph.PostId,
        SUM(CASE WHEN ph.PostHistoryTypeId BETWEEN 4 AND 6 THEN 1 ELSE 0 END) AS EditCount,
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
FETCH FIRST 10 ROWS ONLY;