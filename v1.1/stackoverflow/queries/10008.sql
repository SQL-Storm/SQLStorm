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
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS rank,
        P.PostTypeId
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
        COUNT(B.Id) AS BadgeCount
    FROM 
        Users U
    JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id
),
VoteCounts AS (
    SELECT
        V.PostId,
        COUNT(V.UserId) AS TotalVotes
    FROM
        Votes V
    GROUP BY
        V.PostId
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.DisplayName,
    RP.Reputation,
    BC.BadgeCount,
    CASE
        WHEN RP.rank <= 10 THEN 'Top'
        WHEN RP.rank <= 100 THEN 'Mid'
        ELSE 'Bottom'
    END AS RankTier,
    COALESCE(VC.TotalVotes, 0) AS TotalVotes
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
LEFT JOIN 
    VoteCounts VC ON RP.Id = VC.PostId
WHERE 
    RP.PostTypeId = 1 AND RP.Score > 100
GROUP BY
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.DisplayName,
    RP.Reputation,
    BC.BadgeCount,
    RP.rank,
    RP.PostTypeId,
    VC.TotalVotes
ORDER BY 
    RP.Score DESC, RP.ViewCount DESC
LIMIT 100;