WITH TopUserScores AS (
    SELECT 
        u.Id,
        u.DisplayName,
        SUM(COALESCE(p.Score, 0)) AS TotalScore,
        RANK() OVER (ORDER BY SUM(COALESCE(p.Score, 0)) DESC) AS UserRank
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    WHERE 
        p.PostTypeId IN (1, 2)
        AND p.CreationDate > CAST('2024-10-01' AS date) - INTERVAL '1 year'
    GROUP BY 
        u.Id, u.DisplayName
),
RecentActivity AS (
    SELECT
        ph.PostId,
        COUNT(*) AS ActivityCount
    FROM
        PostHistory ph
    WHERE
        ph.CreationDate > CAST('2024-10-01' AS date) - INTERVAL '1 month'
    GROUP BY
        ph.PostId
),
FinalResults AS (
    SELECT 
        tus.Id,
        tus.DisplayName,
        tus.TotalScore,
        ra.ActivityCount,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        tus.UserRank,
        ROW_NUMBER() OVER (PARTITION BY tus.UserRank ORDER BY ra.ActivityCount DESC) AS RankWithinTier
    FROM
        TopUserScores tus
    LEFT JOIN
        RecentActivity ra ON tus.Id = (
            SELECT p2.OwnerUserId FROM Posts p2 WHERE p2.Id = ra.PostId
        )
    LEFT JOIN
        Badges b ON tus.Id = b.UserId AND b.Class = 1
    WHERE
        tus.UserRank <= 100
    GROUP BY
        tus.Id, tus.DisplayName, tus.TotalScore, ra.ActivityCount, tus.UserRank
)
SELECT 
    fr.Id,
    fr.DisplayName,
    fr.TotalScore,
    COALESCE(fr.ActivityCount, 0) AS RecentActivity,
    COALESCE(fr.GoldBadges, 0) AS GoldBadges,
    fr.RankWithinTier,
    CASE 
        WHEN fr.GoldBadges > 0 THEN 'High Achiever'
        WHEN COALESCE(fr.ActivityCount, 0) > 50 THEN 'Active Contributor'
        ELSE 'Regular User'
    END AS UserCategory
FROM
    FinalResults fr
WHERE
    fr.RankWithinTier <= 10
ORDER BY
    fr.TotalScore DESC, COALESCE(fr.ActivityCount, 0) DESC;