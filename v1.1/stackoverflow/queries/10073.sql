WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.LastActivityDate,
        P.OwnerUserId,
        U.DisplayName AS OwnerDisplayName,
        U.Reputation,
        U.Location,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank,
        COUNT(V.Id) AS TotalVotes
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    LEFT JOIN 
        Votes V ON P.Id = V.PostId
    WHERE 
        P.PostTypeId IN (1, 2)
        AND P.Score > 0
        AND P.ViewCount > 100
        AND P.LastActivityDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY)
    GROUP BY
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.LastActivityDate,
        P.OwnerUserId,
        U.DisplayName,
        U.Reputation,
        U.Location,
        P.PostTypeId
),
BadgeSummary AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        COUNT(B.Id) AS BadgeCount,
        SUM(B.Class) AS TotalBadgeClass
    FROM 
        Users U
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id, U.DisplayName
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.OwnerDisplayName,
    RP.Reputation,
    RP.Location,
    RP.Rank,
    RP.TotalVotes,
    BS.BadgeCount,
    BS.TotalBadgeClass
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeSummary BS ON RP.OwnerUserId = BS.UserId
WHERE 
    RP.Rank <= 10
ORDER BY 
    RP.Score DESC, RP.ViewCount DESC
FETCH FIRST 100 ROWS ONLY;