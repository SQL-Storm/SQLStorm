WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.LastActivityDate,
        U.DisplayName AS OwnerDisplayName,
        U.Reputation,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId = 1 AND P.Score > 0 AND P.ViewCount > 100
),
BadgeCounts AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        COUNT(DISTINCT B.Id) AS BadgeCount
    FROM 
        Users U
    JOIN 
        Badges B ON U.Id = B.UserId
    WHERE 
        B.Class = 1 AND B.TagBased = FALSE
    GROUP BY 
        U.Id, U.DisplayName
),
CommentMetrics AS (
    SELECT 
        PC.Id AS PostId,
        COUNT(C.Id) AS CommentCount,
        MAX(C.Score) AS MaxCommentScore,
        MIN(C.Score) AS MinCommentScore
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
    COALESCE(BC.BadgeCount, 0) AS BadgeCount,
    CO.CommentCount,
    CO.MaxCommentScore,
    CO.MinCommentScore,
    CASE 
        WHEN RP.Score > 1000 THEN 'High'
        WHEN RP.Score > 500 THEN 'Medium'
        ELSE 'Low'
    END AS ScoreTier,
    -- portable extraction of first word from the title: take substring up to first space
    CASE
        WHEN POSITION(' ' IN RP.Title) = 0 THEN RP.Title
        ELSE SUBSTRING(RP.Title FROM 1 FOR POSITION(' ' IN RP.Title) - 1)
    END AS FirstWord,
    CASE 
        WHEN U.Reputation > 10000 THEN 'Veteran'
        WHEN U.Reputation > 1000 THEN 'Experienced'
        ELSE 'Newbie'
    END AS ReputationTier
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerDisplayName = BC.DisplayName
LEFT JOIN 
    CommentMetrics CO ON RP.Id = CO.PostId
LEFT JOIN 
    Users U ON RP.OwnerDisplayName = U.DisplayName
GROUP BY
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.Rank,
    BC.BadgeCount,
    CO.CommentCount,
    CO.MaxCommentScore,
    CO.MinCommentScore,
    U.Reputation,
    RP.OwnerDisplayName
ORDER BY 
    RP.Score DESC, RP.ViewCount DESC
LIMIT 100;