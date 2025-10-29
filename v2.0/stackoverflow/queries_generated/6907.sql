-- {"query": "6907.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 519} 

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
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank,
        CASE 
            WHEN P.PostTypeId = 1 AND P.AcceptedAnswerId IS NOT NULL THEN 
                (SELECT TOP 1 PS.Score FROM Posts PS WHERE PS.Id = P.AcceptedAnswerId)
            ELSE NULL
        END AS AcceptedAnswerScore
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId IN (1, 2) AND P.ViewCount > 100
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
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.Rank,
    RP.AcceptedAnswerScore,
    RP.CreationDate,
    RP.DisplayName,
    RP.Reputation,
    RP.LastAccessDate,
    BC.BadgeCount,
    CASE 
        WHEN RP.Rank <= 10 THEN 'Top'
        WHEN RP.Rank <= 100 THEN 'Middle'
        ELSE 'Bottom'
    END AS RankTier,
    SUBSTRING(RP.Title, 1, 50) AS ShortTitle,
    CASE
        WHEN RP.Score > 100 THEN 'High'
        WHEN RP.Score BETWEEN 10 AND 100 THEN 'Medium'
        ELSE 'Low'
    END AS ScoreTier
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.UserId = BC.UserId
WHERE 
    (RP.Score > 100 OR RP.ViewCount > 1000)
    AND RP.Rank <= 100
ORDER BY 
    RP.Score DESC, RP.ViewCount DESC;
