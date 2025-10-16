-- {"query": "23017.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 882} 

WITH TopUsers AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS UserRank,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COUNT(p.Id) AS PostCount
    FROM Users u
    LEFT OUTER JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.Reputation, u.DisplayName
    HAVING u.Reputation > 10000
),
UserBadges AS (
    SELECT 
        b.UserId,
        COUNT(b.Id) AS BadgeCount,
        STRING_AGG(CASE WHEN b.Class = 1 THEN b.Name ELSE NULL END, ', ') AS GoldBadges
    FROM Badges b
    WHERE b.TagBased = 0
    GROUP BY b.UserId
),
PostAnalytics AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 0) AS PositiveComments,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousScore,
        CASE 
            WHEN p.Score IS NULL THEN 0 
            WHEN p.Score > 0 THEN p.Score * 1.5 
            ELSE ABS(p.Score) * -1 
        END AS AdjustedScore,
        UPPER(SUBSTRING(p.Title, 1, 10)) || '...' AS TruncatedTitle
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
CombinedData AS (
    SELECT 
        tu.UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.UserRank,
        tu.TotalPostScore,
        tu.PostCount,
        ub.BadgeCount,
        ub.GoldBadges,
        pa.PostId,
        pa.Score,
        pa.ViewCount,
        pa.PositiveComments,
        pa.PreviousScore,
        pa.AdjustedScore,
        pa.TruncatedTitle,
        (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = pa.PostId AND v.VoteTypeId = 8 AND v.BountyAmount IS NOT NULL) AS AvgBounty
    FROM TopUsers tu
    LEFT OUTER JOIN UserBadges ub ON tu.UserId = ub.UserId
    LEFT OUTER JOIN PostAnalytics pa ON tu.UserId = pa.OwnerUserId
    WHERE tu.UserRank <= 100
    UNION
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        NULL AS UserRank,
        0 AS TotalPostScore,
        0 AS PostCount,
        0 AS BadgeCount,
        NULL AS GoldBadges,
        NULL AS PostId,
        NULL AS Score,
        NULL AS ViewCount,
        0 AS PositiveComments,
        NULL AS PreviousScore,
        0 AS AdjustedScore,
        NULL AS TruncatedTitle,
        NULL AS AvgBounty
    FROM Users u
    WHERE u.Reputation < 100 AND NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)
)
SELECT 
    cd.UserId,
    cd.DisplayName,
    cd.Reputation,
    cd.UserRank,
    cd.TotalPostScore,
    cd.PostCount,
    cd.BadgeCount,
    cd.GoldBadges,
    cd.PostId,
    cd.Score,
    cd.ViewCount,
    cd.PositiveComments,
    CASE WHEN cd.PreviousScore IS NULL THEN 'No Previous' ELSE CAST(cd.PreviousScore AS VARCHAR) END AS PreviousScoreStr,
    cd.AdjustedScore,
    cd.TruncatedTitle,
    cd.AvgBounty,
    (SELECT COUNT(ph.Id) FROM PostHistory ph WHERE ph.PostId = cd.PostId AND ph.PostHistoryTypeId IN (4,5,6) AND ph.CreationDate > NOW() - INTERVAL '1 YEAR') AS RecentEdits
FROM CombinedData cd
WHERE cd.AdjustedScore > 0 OR cd.AvgBounty IS NOT NULL
ORDER BY cd.UserRank ASC, cd.AdjustedScore DESC;
