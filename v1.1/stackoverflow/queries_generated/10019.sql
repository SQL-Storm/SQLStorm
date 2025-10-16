-- {"query": "10019.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 577} 

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
BadgesSummary AS (
    SELECT 
        B.UserId,
        COUNT(DISTINCT B.Id) AS total_badges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS gold_badges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS silver_badges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS bronze_badges
    FROM 
        Badges B
    GROUP BY 
        B.UserId
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
    B.total_badges,
    B.gold_badges,
    B.silver_badges,
    B.bronze_badges,
    CASE 
        WHEN COUNT(DISTINCT CASE WHEN V.VoteTypeId = 2 THEN V.PostId END) OVER (PARTITION BY RP.Id) > 5 THEN 'HighlyUpvoted'
        ELSE 'Regular'
    END AS upvote_status
FROM 
    RankedPosts RP
LEFT JOIN 
    Users U ON RP.OwnerUserId = U.Id
LEFT JOIN 
    BadgesSummary B ON RP.OwnerUserId = B.UserId
LEFT JOIN 
    Votes V ON RP.Id = V.PostId
WHERE 
    RP.rank <= 10
    AND U.Reputation > 100
    AND (RP.Score > 100 OR RP.ViewCount > 1000)
GROUP BY 
    RP.Id, RP.Title, RP.Score, RP.ViewCount, RP.CreationDate, RP.rank, U.DisplayName, U.Reputation, B.total_badges, B.gold_badges, B.silver_badges, B.bronze_badges
ORDER BY 
    RP.Score DESC, RP.rank ASC;
