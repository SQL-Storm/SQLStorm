-- {"query": "10100.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 523} 

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
        B.Class = 1 AND B.TagBased = 0
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
    U.DisplayName,
    U.Reputation,
    BC.BadgeCount,
    CASE 
        WHEN RP.rank <= 3 THEN 'Top'
        WHEN RP.rank <= 10 THEN 'High'
        ELSE 'Low'
    END AS RankStatus,
    STRING_AGG(T.TagName, ', ') WITHIN GROUP AS ORDER BY T.Count DESC AS TagList
FROM 
    RankedPosts RP
LEFT JOIN 
    Users U ON RP.OwnerUserId = U.Id
LEFT JOIN 
    PostHistory PH ON RP.Id = PH.PostId AND PH.PostHistoryTypeId = 10
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
LEFT JOIN 
    POST_TAGS PT ON RP.Id = PT.PostId
LEFT JOIN 
    Tags T ON PT.TagId = T.Id
WHERE 
    RP.rank <= 10 AND U.Reputation > 100 AND PH.Comment IS NULL
GROUP BY 
    RP.Id, RP.Title, RP.Score, RP.ViewCount, RP.CreationDate, RP.rank, U.DisplayName, U.Reputation, BC.BadgeCount
ORDER BY 
    RP.rank, RP.Score DESC;
