-- {"query": "6787.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 477} 

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
        P.PostTypeId != 3 AND P.PostTypeId != 4 AND P.PostTypeId != 5
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
        MAX(Score) AS max_comment_score
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
    CS.max_comment_score,
    CASE 
        WHEN RP.Score > 100 THEN 'High'
        ELSE 'Low'
    END AS ScoreTier,
    CASE 
        WHEN U.Reputation > 1000 THEN 'High'
        ELSE 'Low'
    END AS ReputationTier
FROM 
    RankedPosts RP
LEFT JOIN 
    Users U ON RP.OwnerUserId = U.Id
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
LEFT JOIN 
    CommentStats CS ON RP.Id = CS.PostId
WHERE 
    (RP.Score > 10 OR RP.ViewCount > 100)
    AND (RP.rank <= 3 OR CS.comment_count > 10)
ORDER BY 
    RP.rank, 
    RP.Score DESC;
