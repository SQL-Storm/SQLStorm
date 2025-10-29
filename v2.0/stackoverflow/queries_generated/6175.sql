-- {"query": "6175.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 362} 

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
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.LastActivityDate DESC) AS Rank
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
    TO_CHAR(RP.CreationDate, 'YYYY-MM-DD') AS CreationDate,
    TO_CHAR(RP.LastActivityDate, 'YYYY-MM-DD') AS LastActivityDate,
    RP.OwnerDisplayName,
    RP.Reputation,
    RC.BadgeCount,
    ROW_NUMBER() OVER (ORDER BY RP.Score DESC, RP.Rank) AS GlobalRank
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts RC ON RP.OwnerUserId = RC.UserId
WHERE 
    RP.Rank <= 10
ORDER BY 
    GlobalRank;
