WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.LastActivityDate,
        P.OwnerUserId,
        U.DisplayName,
        U.Reputation,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId = 1 AND P.Score > 0 AND P.LastActivityDate > P.CreationDate
),
BadgeCounts AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        COUNT(DISTINCT B.Id) AS BadgeCount
    FROM 
        Users U
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id, U.DisplayName
),
CommentMetrics AS (
    SELECT 
        PC.Id AS PostId,
        COUNT(C.Id) AS CommentCount,
        SUM(C.Score) AS TotalCommentScore
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
    RP.LastActivityDate,
    RP.Rank,
    RP.OwnerUserId,
    RP.DisplayName AS OwnerDisplayName,
    RP.Reputation,
    BC.BadgeCount,
    CM.CommentCount,
    COALESCE(CM.TotalCommentScore, 0) AS TotalCommentScore,
    CASE 
        WHEN RP.Score > 100 THEN 'High'
        WHEN RP.Score BETWEEN 50 AND 100 THEN 'Medium'
        ELSE 'Low'
    END AS ScoreTier,
    SUBSTRING(
        SPLIT_PART(RP.Title, ' ', 2), 1, NULL
    ) AS ShortTitle
FROM 
    RankedPosts RP
LEFT JOIN 
    Users U ON RP.OwnerUserId = U.Id
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
LEFT JOIN 
    CommentMetrics CM ON RP.Id = CM.PostId
ORDER BY 
    RP.Rank, RP.Score DESC;