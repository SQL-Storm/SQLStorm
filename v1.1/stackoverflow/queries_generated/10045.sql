-- {"query": "10045.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 435} 

WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        U.DisplayName,
        U.Reputation,
        U.LastAccessDate,
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
        COUNT(DISTINCT B.Id) AS BadgeCount
    FROM 
        Users U
    LEFT JOIN 
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
    RP.Rank,
    U.DisplayName,
    U.Reputation,
    U.LastAccessDate,
    RC.BadgeCount,
    CASE 
        WHEN RP.Rank <= 3 THEN 'Top'
        WHEN RP.Rank <= 10 THEN 'High'
        ELSE 'Low'
    END AS RankCategory,
    SUM(V.BountyAmount) OVER (PARTITION BY RP.Id) AS TotalBounty
FROM 
    RankedPosts RP
LEFT JOIN 
    Users U ON RP.OwnerUserId = U.Id
LEFT JOIN 
    BadgeCounts RC ON RP.OwnerUserId = RC.UserId
LEFT JOIN 
    Votes V ON RP.Id = V.PostId AND V.VoteTypeId = 8
WHERE 
    U.Reputation > 100
    AND RP.Rank <= 10
ORDER BY 
    RP.Score DESC, RP.ViewCount DESC;
