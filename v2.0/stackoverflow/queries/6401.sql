-- {"query": "6401.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 403}
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
        P.OwnerUserId,
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
    COALESCE(BC.BadgeCount, 0) AS GoldBadgeCount,
    CASE 
        WHEN RP.Score > 100 THEN 'High Scoring'
        WHEN RP.ViewCount > 1000 THEN 'High Traffic'
        ELSE 'Regular'
    END AS PostType,
    (
        SELECT 
            COUNT(*) 
        FROM 
            Votes V
        WHERE 
            V.PostId = RP.Id AND V.VoteTypeId IN (2, 15)
    ) AS PositiveFeedbackCount
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
ORDER BY 
    RP.Rank, 
    RP.Score DESC;