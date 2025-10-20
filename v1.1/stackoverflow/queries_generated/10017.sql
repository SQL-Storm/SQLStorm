-- {"query": "10017.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 434} 

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
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank
    FROM Posts P
    JOIN Users U ON P.OwnerUserId = U.Id
    WHERE P.PostTypeId = 1 AND P.Score > 0 AND P.ViewCount > 100
),
BadgeCounts AS (
    SELECT 
        B.UserId,
        COUNT(B.Id) AS BadgeCount
    FROM Badges B
    WHERE B.Class = 1 AND B.TagBased = FALSE
    GROUP BY B.UserId
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.Rank,
    RP.DisplayName,
    RP.Reputation,
    COALESCE(BC.BadgeCount, 0) AS BadgeCount,
    CASE 
        WHEN RP.Score > 100 THEN 'High'
        WHEN RP.ViewCount > 1000 THEN 'Popular'
        ELSE 'Regular'
    END AS Popularity,
    SUBSTRING(RP.Title FROM 1 FOR 30) AS ShortTitle,
    CASE 
        WHEN RP.CreationDate < '2020-01-01' THEN 'Old'
        ELSE 'New'
    END AS Age,
    (
        SELECT COUNT(*) 
        FROM Votes V 
        WHERE V.PostId = RP.Id AND V.VoteTypeId IN (2, 3)
    ) AS NetVotes
FROM RankedPosts RP
LEFT JOIN BadgeCounts BC ON RP.OwnerUserId = BC.UserId
ORDER BY RP.Rank, RP.Score DESC;
