-- {"query": "6370.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 538}
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
        P.PostTypeId,
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
    WHERE 
        Class = 1 AND TagBased = FALSE
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
    BC.badge_count,
    CS.comment_count,
    COALESCE(CS.thanks_count, 0) AS thanks_count,
    CASE 
        WHEN RP.Score > 10 AND RP.ViewCount > 100 THEN 'Popular'
        WHEN RP.Score > 5 AND RP.ViewCount > 50 THEN 'Active'
        ELSE 'Inactive'
    END AS activity_level,
    CASE
        WHEN RP.PostTypeId = 1 THEN 'Question'
        WHEN RP.PostTypeId = 2 THEN 'Answer'
        ELSE NULL
    END AS post_type
FROM 
    RankedPosts RP
LEFT JOIN 
    Users U ON RP.OwnerUserId = U.Id
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
LEFT JOIN 
    CommentStats CS ON RP.Id = CS.PostId
WHERE 
    (RP.rank <= 3 OR RP.Score > 100) 
    AND (COALESCE(BC.badge_count, 0) >= 3 OR RP.ViewCount > 1000)
ORDER BY 
    RP.rank, RP.Score DESC;