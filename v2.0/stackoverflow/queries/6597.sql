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
        P.PostTypeId NOT IN (3,4,5,6,7,8)
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
),
CommentedPosts AS (
    SELECT 
        PC.Id AS PostId,
        COUNT(C.Id) AS CommentCount
    FROM 
        Posts PC
    LEFT JOIN 
        Comments C ON PC.Id = C.PostId
    GROUP BY 
        PC.Id
)
SELECT 
    RP.Id AS PostId,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.rank,
    COALESCE(CC.CommentCount, 0) AS CommentCount,
    RP.DisplayName,
    RP.Reputation,
    BC.BadgeCount,
    CASE
        WHEN RP.Score >= 100 THEN 'High'
        WHEN RP.Score BETWEEN 50 AND 99 THEN 'Medium'
        ELSE 'Low'
    END AS ScoreTier,
    CASE
        WHEN RP.ViewCount >= 1000 THEN 'High'
        WHEN RP.ViewCount BETWEEN 500 AND 999 THEN 'Medium'
        ELSE 'Low'
    END AS ViewTier
FROM 
    RankedPosts RP
LEFT JOIN 
    CommentedPosts CC ON RP.Id = CC.PostId
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
ORDER BY 
    RP.rank, RP.Score DESC, RP.ViewCount DESC;