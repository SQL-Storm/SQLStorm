-- {"query": "10027.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 516} 

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
    U.DisplayName,
    U.Reputation,
    BC.BadgeCount,
    CASE 
        WHEN RP.Rank <= 3 THEN 'Top'
        WHEN RP.Rank <= 10 THEN 'High'
        ELSE 'Low'
    END AS RankStatus,
    SUBSTRING(U.AboutMe, 1, 50) AS AboutMeSnippet,
    CASE
        WHEN U.Location IS NULL THEN 'Unknown'
        ELSE U.Location
    END AS Location,
    (
        SELECT 
            STRING_AGG(T.TagName, ', ')
        FROM 
            Tags T
        WHERE 
            T.ExcerptPostId = RP.Id
    ) AS Tags,
    (
        SELECT 
            COUNT(*) 
        FROM 
            Votes V
        WHERE 
            V.PostId = RP.Id AND V.VoteTypeId = 2
    ) AS UpVoteCount
FROM 
    RankedPosts RP
JOIN 
    Users U ON RP.OwnerDisplayName = U.DisplayName
LEFT JOIN 
    BadgeCounts BC ON U.Id = BC.UserId
WHERE 
    RP.Rank <= 10 AND U.Reputation > 1000
ORDER BY 
    RP.Rank, RP.Score DESC;
