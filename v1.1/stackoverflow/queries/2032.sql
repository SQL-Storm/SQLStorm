WITH UserBadges AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) AS TotalBadges,
        MAX(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS HasGoldBadge
    FROM 
        Users u
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    GROUP BY 
        u.Id, u.DisplayName
),
RecentPosts AS (
    SELECT 
        p.Id,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.PostTypeId,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM 
        Posts p
    WHERE 
        p.PostTypeId IN (1, 2) AND p.CreationDate > (CAST('2024-10-01' AS date) - INTERVAL '30 days')
),
TopScoringPosts AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        MAX(p.Score) AS MaxScore
    FROM 
        Posts p
    WHERE 
        p.Score IS NOT NULL AND (SELECT COUNT(1) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 0) > 5
    GROUP BY 
        p.Id, p.OwnerUserId
),
UserActivityAndRating AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COALESCE((SELECT SUM(v.BountyAmount) FROM Votes v WHERE v.UserId = u.Id AND v.BountyAmount IS NOT NULL), 0) AS TotalBountyAwarded,
        COALESCE(SUM(p.Score), 0) AS TotalScore
    FROM 
        Users u
    LEFT JOIN 
        RecentPosts p ON u.Id = p.OwnerUserId
    GROUP BY 
        u.Id, u.DisplayName
)
SELECT 
    uba.UserId,
    uba.DisplayName,
    uba.TotalBadges,
    CASE WHEN uba.HasGoldBadge = 1 THEN 'Yes' ELSE 'No' END AS HasGoldBadge,
    -- use explicit numeric division and formatting portable across dialects: compute ratio as numeric and round to 2 decimals
    ROUND(CAST(uar.TotalBountyAwarded AS NUMERIC) / NULLIF(uar.TotalScore + 1, 0), 2) AS BountyToScoreRatio,
    COALESCE(tp.MaxScore, 0) AS TopPostScore
FROM 
    UserBadges uba
JOIN 
    UserActivityAndRating uar ON uba.UserId = uar.UserId
LEFT JOIN 
    TopScoringPosts tp ON uba.UserId = tp.OwnerUserId
WHERE 
    uar.TotalScore >= 100
ORDER BY 
    uar.TotalBountyAwarded DESC, tp.MaxScore DESC;