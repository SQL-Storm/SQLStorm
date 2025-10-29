-- {"query": "6263.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 512} 

WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.LastActivityDate,
        U.DisplayName,
        P.OwnerUserId,
        P.LastEditorUserId,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS rank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId = 1 AND P.Score > 0 AND P.ViewCount > 100
),
BadgeCounts AS (
    SELECT 
        B.UserId,
        COUNT(B.Id) AS badge_count
    FROM 
        Badges B
    GROUP BY 
        B.UserId
),
CommentStats AS (
    SELECT 
        P.Id AS PostId,
        COUNT(C.Id) AS comment_count,
        MAX(C.Score) AS max_comment_score
    FROM 
        Posts P
    LEFT JOIN 
        Comments C ON P.Id = C.PostId
    WHERE 
        P.PostTypeId = 1
    GROUP BY 
        P.Id
)
SELECT 
    RP.Id AS PostId,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.DisplayName,
    RP.OwnerUserId,
    RP.LastEditorUserId,
    COALESCE(BC.badge_count, 0) AS badge_count,
    CS.comment_count,
    CS.max_comment_score,
    CASE 
        WHEN RP.rank <= 1 THEN 'Top'
        WHEN RP.rank <= 10 THEN 'Top 10'
        ELSE 'Other'
    END AS rank_group
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
LEFT JOIN 
    CommentStats CS ON RP.Id = CS.PostId
WHERE 
    EXISTS (
        SELECT 1 
        FROM Votes V 
        WHERE V.PostId = RP.Id AND V.VoteTypeId = 2
    )
ORDER BY 
    RP.Score DESC, 
    RP.ViewCount DESC;
