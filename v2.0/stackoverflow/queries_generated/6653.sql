-- {"query": "6653.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 476} 

WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.LastActivityDate,
        U.DisplayName,
        U.Reputation,
        U.LastAccessDate,
        ROW_NUMBER() OVER (ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank
    FROM 
        Posts P
    JOIN 
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
    RP.Rank,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.DisplayName,
    RP.Reputation,
    RP.LastAccessDate,
    BC.BadgeCount,
    CASE 
        WHEN RP.Score > 100 THEN 'High'
        WHEN RP.ViewCount > 1000 THEN 'Popular'
        ELSE 'Regular'
    END AS Popularity,
    CASE 
        WHEN RP.CreationDate < '2020-01-01' THEN 'Old'
        ELSE 'Recent'
    END AS Age,
    SUBSTRING(RP.Title, 1, 50) AS ShortTitle,
    U.Location,
    U.WebsiteUrl,
    U.AboutMe
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.DisplayName = BC.UserId
JOIN 
    Users U ON RP.DisplayName = U.Id
WHERE 
    (RP.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) OR RP.ViewCount > (SELECT AVG(ViewCount) FROM Posts WHERE PostTypeId = 1))
ORDER BY 
    RP.Rank;
