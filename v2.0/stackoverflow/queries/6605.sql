-- {"query": "6605.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 472}
WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.OwnerUserId,
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
        SUM(B.Class) AS badge_points
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
    B.badge_points,
    CASE 
        WHEN RP.rank = 1 THEN 'Top Score'
        WHEN RP.rank <= 10 THEN 'Top Ten'
        ELSE 'Other'
    END AS rank_label,
    COUNT(DISTINCT V.Id) AS total_votes
FROM 
    RankedPosts RP
LEFT JOIN 
    Users U ON RP.OwnerUserId = U.Id
LEFT JOIN 
    BadgesSummary B ON RP.OwnerUserId = B.UserId
LEFT JOIN 
    Votes V ON RP.Id = V.PostId
WHERE 
    EXISTS (
        SELECT 1 
        FROM PostHistory PH 
        WHERE PH.PostId = RP.Id AND PH.PostHistoryTypeId = 10
    )
GROUP BY 
    RP.Id, RP.Title, RP.Score, RP.ViewCount, RP.CreationDate, RP.rank, RP.OwnerUserId, U.DisplayName, U.Reputation, B.total_badges, B.badge_points
ORDER BY 
    total_votes DESC, RP.rank;