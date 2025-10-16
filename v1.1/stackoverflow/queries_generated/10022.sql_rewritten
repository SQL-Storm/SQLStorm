-- {"query": "10022.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 437} 
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
        U.AccountId,
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
    RP.LastActivityDate,
    RP.Rank,
    U.DisplayName AS OwnerDisplayName,
    U.Reputation,
    U.AccountId,
    RC.BadgeCount,
    CASE 
        WHEN RP.Score > 100 THEN 'High'
        WHEN RP.ViewCount > 1000 THEN 'Popular'
        ELSE 'Regular'
    END AS Popularity,
    SUBSTRING(U.AboutMe, 1, 100) AS AboutMeSnippet
FROM 
    RankedPosts RP
LEFT JOIN 
    Users U ON RP.OwnerDisplayName = U.DisplayName
LEFT JOIN 
    BadgeCounts RC ON U.Id = RC.UserId
WHERE 
    (RP.Rank <= 3 OR RP.Score > 500) 
    AND U.AccountId IS NOT NULL
ORDER BY 
    RP.Rank, RP.Score DESC, RP.ViewCount DESC;