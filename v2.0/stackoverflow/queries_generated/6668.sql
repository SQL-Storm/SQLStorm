-- {"query": "6668.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 507} 

WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.LastActivityDate,
        P.OwnerUserId,
        U.DisplayName AS OwnerDisplayName,
        U.Reputation,
        U.Location,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId IN (1, 2) AND P.Score > 0 AND P.ViewCount > 100
),
BadgeCounts AS (
    SELECT 
        UserId,
        COUNT(DISTINCT Id) AS BadgeCount
    FROM 
        Badges
    GROUP BY 
        UserId
),
CommentStats AS (
    SELECT 
        PostId,
        COUNT(Id) AS CommentCount,
        MAX(Score) AS MaxCommentScore
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
    TO_CHAR(RP.CreationDate, 'YYYY-MM-DD') AS CreationDate,
    TO_CHAR(RP.LastActivityDate, 'YYYY-MM-DD') AS LastActivityDate,
    RP.OwnerUserId,
    RP.OwnerDisplayName,
    RP.Reputation,
    RP.Location,
    COALESCE(BC.BadgeCount, 0) AS BadgeCount,
    CS.CommentCount,
    CS.MaxCommentScore,
    ROW_NUMBER() OVER (ORDER BY RP.Score DESC, RP.ViewCount DESC) AS GlobalRank
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
LEFT JOIN 
    CommentStats CS ON RP.Id = CS.PostId
WHERE 
    EXISTS (
        SELECT 1
        FROM 
            Tags T
        WHERE 
            T.Id IN (
                SELECT Id
                FROM Tags
                WHERE TagName IN ('SQL', 'Performance', 'Benchmarking')
            )
            AND T.PostId = RP.Id
    )
ORDER BY 
    GlobalRank;
