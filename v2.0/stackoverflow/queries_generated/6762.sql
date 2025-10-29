-- {"query": "6762.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 465} 

WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
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
    WHERE 
        B.Class = 1 AND B.TagBased = FALSE
    GROUP BY 
        U.Id
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.rank,
    RP.DisplayName,
    RP.Reputation,
    B.BadgeCount,
    CASE 
        WHEN RP.Score > 100 AND RP.ViewCount > 1000 THEN 'Popular'
        WHEN RP.Score > 50 THEN 'High Scoring'
        ELSE 'Regular'
    END AS PostType,
    COALESCE(SUM(V.BountyAmount), 0) AS TotalBounty
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts B ON RP.OwnerUserId = B.UserId
LEFT JOIN 
    Votes V ON RP.Id = V.PostId AND V.VoteTypeId = 8
WHERE 
    RP.rank <= 10
GROUP BY 
    RP.Id, RP.Title, RP.Score, RP.ViewCount, RP.CreationDate, RP.rank, RP.DisplayName, RP.Reputation, B.BadgeCount
ORDER BY 
    TotalBounty DESC, RP.Score DESC
LIMIT 100;
