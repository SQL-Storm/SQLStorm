-- {"query": "6795.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 562} 
WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        U.DisplayName,
        P.OwnerUserId,
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
        UserId,
        COUNT(DISTINCT Id) AS badge_count
    FROM 
        Badges
    GROUP BY 
        UserId
),
CommentStats AS (
    SELECT 
        PostId,
        COUNT(Id) AS comment_count,
        MAX(CASE WHEN Text LIKE '%thank%' THEN 1 ELSE 0 END) AS thanks_count
    FROM 
        Comments
    GROUP BY 
        PostId
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
    COALESCE(BC.badge_count, 0) AS badge_count,
    CS.comment_count,
    CS.thanks_count,
    MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.Comment ELSE NULL END) AS close_reason,
    MAX(CASE WHEN PH.PostHistoryTypeId = 33 THEN PH.Comment ELSE NULL END) AS post_notice
FROM 
    RankedPosts RP
LEFT JOIN 
    Users U ON RP.OwnerUserId = U.Id
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
LEFT JOIN 
    CommentStats CS ON RP.Id = CS.PostId
LEFT JOIN 
    PostHistory PH ON RP.Id = PH.PostId
WHERE 
    RP.rank <= 10
    AND EXISTS (
        SELECT 1 
        FROM Votes V 
        WHERE V.PostId = RP.Id AND V.VoteTypeId = 2
    )
GROUP BY 
    RP.Id, RP.Title, RP.Score, RP.ViewCount, RP.CreationDate, RP.rank, U.DisplayName, U.Reputation, BC.badge_count, CS.comment_count, CS.thanks_count
ORDER BY 
    RP.rank, RP.Score DESC;