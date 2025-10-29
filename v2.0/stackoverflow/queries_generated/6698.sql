-- {"query": "6698.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 513} 

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
    RP.DisplayName,
    RP.Reputation,
    B.total_badges,
    B.badge_points,
    COUNT(DISTINCT V.PostId) OVER (PARTITION BY RP.Id) AS total_votes,
    COUNT(DISTINCT PL.RelatedPostId) OVER (PARTITION BY RP.Id) AS linked_posts_count,
    MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.Comment ELSE NULL END) OVER (PARTITION BY RP.Id) AS close_reason,
    MAX(CASE WHEN PH.PostHistoryTypeId = 33 THEN PH.Comment ELSE NULL END) OVER (PARTITION BY RP.Id) AS post_notice
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgesSummary B ON RP.DisplayName = B.UserId
LEFT JOIN 
    Votes V ON RP.Id = V.PostId
LEFT JOIN 
    PostLinks PL ON RP.Id = PL.PostId
LEFT JOIN 
    PostHistory PH ON RP.Id = PH.PostId
WHERE 
    RP.rank <= 10
    AND EXISTS (
        SELECT 1 
        FROM Comments C 
        WHERE C.PostId = RP.Id AND C.Score > 0
    )
ORDER BY 
    RP.Score DESC, RP.ViewCount DESC
LIMIT 100;
