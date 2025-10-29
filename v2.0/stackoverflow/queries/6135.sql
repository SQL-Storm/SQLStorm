-- {"query": "6135.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 532}
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
        P.PostTypeId NOT IN (3, 4, 5)
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
        MAX(CASE WHEN Text LIKE '%bug%' THEN 1 ELSE 0 END) AS bug_comment_count
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
    RP.OwnerUserId,
    U.DisplayName,
    U.Reputation,
    BC.badge_count,
    CS.comment_count,
    CS.bug_comment_count,
    CASE 
        WHEN RP.Score > 100 THEN 'High'
        WHEN RP.Score BETWEEN 50 AND 100 THEN 'Medium'
        ELSE 'Low'
    END AS score_level,
    CASE 
        WHEN RP.ViewCount > 1000 THEN 'Popular'
        WHEN RP.ViewCount BETWEEN 100 AND 1000 THEN 'Moderate'
        ELSE 'Less Popular'
    END AS view_level
FROM 
    RankedPosts RP
LEFT JOIN 
    Users U ON RP.OwnerUserId = U.Id
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
LEFT JOIN 
    CommentStats CS ON RP.Id = CS.PostId
WHERE 
    (RP.Score > 10 OR RP.ViewCount > 1000)
    AND (COALESCE(BC.badge_count, 0) > 3 OR COALESCE(CS.comment_count, 0) > 5)
GROUP BY
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.rank,
    RP.OwnerUserId,
    U.DisplayName,
    U.Reputation,
    BC.badge_count,
    CS.comment_count,
    CS.bug_comment_count
ORDER BY 
    RP.rank, 
    score_level DESC, 
    view_level DESC;