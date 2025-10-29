-- {"query": "6038.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 423}
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
    GROUP BY 
        U.Id
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    CAST(RP.CreationDate AS DATE) AS CreationDate,
    RP.DisplayName,
    RP.Reputation,
    RP.rank,
    BC.BadgeCount,
    CASE
        WHEN RP.rank <= 3 THEN 'Top'
        WHEN RP.rank <= 10 THEN 'High'
        ELSE 'Low'
    END AS RankStatus
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
WHERE 
    EXISTS (
        SELECT 1 
        FROM Votes V 
        WHERE V.PostId = RP.Id AND V.VoteTypeId = 2
    )
AND 
    NOT EXISTS (
        SELECT 1 
        FROM PostHistory PH 
        WHERE PH.PostId = RP.Id AND PH.PostHistoryTypeId = 10
    )
GROUP BY
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    CAST(RP.CreationDate AS DATE),
    RP.DisplayName,
    RP.Reputation,
    RP.rank,
    BC.BadgeCount
ORDER BY 
    RP.rank, 
    RP.Score DESC, 
    RP.ViewCount DESC;