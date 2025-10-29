WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        U.DisplayName,
        U.Reputation,
        P.OwnerUserId AS UserId,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS rank
    FROM 
        Posts P
    JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId IN (1, 2) AND P.Score > 0
),
BadgeCounts AS (
    SELECT 
        U.Id AS UserId,
        COUNT(DISTINCT B.Id) AS BadgeCount
    FROM 
        Users U
    JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.DisplayName,
    RP.Reputation,
    RP.rank,
    BC.BadgeCount,
    CASE 
        WHEN RP.Score > 100 AND RP.ViewCount > 1000 THEN 'High Impact'
        WHEN RP.Score > 50 AND RP.ViewCount > 500 THEN 'Moderate Impact'
        ELSE 'Low Impact'
    END AS ImpactLevel,
    COALESCE(SUM(V.BountyAmount), 0) AS TotalBounty
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.UserId = BC.UserId
LEFT JOIN 
    (
     SELECT 
        PostId, 
        SUM(BountyAmount) AS BountyAmount
     FROM 
        Votes
     WHERE 
        VoteTypeId = 8
     GROUP BY 
        PostId
    ) V ON RP.Id = V.PostId
GROUP BY 
    RP.Id, RP.Title, RP.Score, RP.ViewCount, RP.CreationDate, RP.DisplayName, RP.Reputation, RP.rank, RP.UserId, BC.BadgeCount
ORDER BY 
    RP.rank, RP.Score DESC;