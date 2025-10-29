-- {"query": "6978.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 490}
WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.LastActivityDate,
        P.OwnerUserId,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank
    FROM 
        Posts P
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
    SUBSTRING(U.AboutMe FROM 1 FOR 50) AS AboutMeSnippet,
    CASE
        WHEN U.Reputation > 10000 THEN 'Veteran'
        WHEN U.Reputation > 1000 THEN 'Experienced'
        ELSE 'Newbie'
    END AS ReputationLevel
FROM 
    RankedPosts RP
JOIN 
    Users U ON RP.OwnerUserId = U.Id
LEFT JOIN 
    BadgeCounts BC ON U.Id = BC.UserId
WHERE 
    RP.Score > (
        SELECT AVG(p2.Score) + 2 * STDDEV_SAMP(p2.Score)
        FROM Posts p2
        WHERE p2.PostTypeId = 1
    )
    AND RP.ViewCount > (
        SELECT AVG(p3.ViewCount) + 2 * STDDEV_SAMP(p3.ViewCount)
        FROM Posts p3
        WHERE p3.PostTypeId = 1
    )
GROUP BY
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.Rank,
    RP.OwnerUserId,
    U.DisplayName,
    U.Reputation,
    BC.BadgeCount,
    U.AboutMe
ORDER BY 
    RP.Rank ASC;