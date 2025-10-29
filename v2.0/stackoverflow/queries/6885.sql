-- {"query": "6885.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 462}
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
        P.PostTypeId NOT IN (3, 4, 5)
),
BadgeCounts AS (
    SELECT 
        UserId,
        COUNT(DISTINCT Id) AS badge_count
    FROM 
        Badges
    WHERE 
        Class = 1 AND TagBased = FALSE
    GROUP BY 
        UserId
),
CommentStats AS (
    SELECT 
        PostId,
        COUNT(Id) AS comment_count,
        MAX(COALESCE(Score, 0)) AS max_comment_score
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
    RP.DisplayName,
    RP.Reputation,
    BC.badge_count,
    CS.comment_count,
    CASE 
        WHEN CS.max_comment_score > 10 THEN 'High'
        WHEN CS.max_comment_score > 0 THEN 'Medium'
        ELSE 'Low'
    END AS comment_activity,
    CASE 
        WHEN RP.Score > 1000 THEN 'High'
        WHEN RP.Score > 0 THEN 'Medium'
        ELSE 'Low'
    END AS post_activity
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
LEFT JOIN 
    CommentStats CS ON RP.Id = CS.PostId
WHERE 
    RP.rank <= 10
ORDER BY 
    RP.Score DESC, RP.ViewCount DESC;