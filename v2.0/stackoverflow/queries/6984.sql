WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        U.DisplayName,
        U.Reputation,
        U.Id AS OwnerUserId,
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
    B.BadgeCount,
    CASE 
        WHEN RP.rank <= 3 THEN 'Top'
        WHEN RP.rank <= 10 THEN 'High'
        ELSE 'Low'
    END AS RankStatus,
    SUBSTRING(RP.Title FROM 1 FOR 10) AS ShortTitle,
    CASE 
        WHEN COALESCE(B.BadgeCount, 0) >= 5 THEN 'Elite'
        WHEN COALESCE(B.BadgeCount, 0) >= 2 THEN 'Active'
        ELSE 'Inactive'
    END AS UserStatus,
    SUM(V.BountyAmount) OVER (PARTITION BY RP.Id ORDER BY V.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeBounty
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts B ON RP.OwnerUserId = B.UserId
LEFT JOIN 
    Votes V ON RP.Id = V.PostId AND V.VoteTypeId = 8
WHERE 
    RP.rank <= 10
AND 
    EXISTS (
        SELECT 1
        FROM PostLinks PL
        WHERE PL.PostId = RP.Id AND PL.LinkTypeId = 1
    )
ORDER BY 
    RP.rank, RP.Score DESC;