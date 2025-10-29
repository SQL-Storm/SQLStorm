WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.OwnerUserId,
        U.DisplayName,
        U.Reputation,
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
    COALESCE(BC.BadgeCount, 0) AS BadgeCount,
    COALESCE(SUM(V.VoteTypeId), 0) AS TotalVotes,
    CASE 
        WHEN RP.rank = 1 THEN 'Top Score'
        WHEN RP.rank <= 10 THEN 'Top Ten'
        ELSE 'Other'
    END AS RankCategory
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
LEFT JOIN 
    Votes V ON RP.Id = V.PostId
GROUP BY 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.DisplayName,
    RP.Reputation,
    RP.rank,
    RP.OwnerUserId,
    BC.BadgeCount
HAVING 
    RP.rank <= 10 OR COALESCE(BC.BadgeCount, 0) >= 5
ORDER BY 
    TotalVotes DESC, RP.rank ASC;