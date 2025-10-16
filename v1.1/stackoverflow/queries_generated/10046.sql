-- {"query": "10046.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 600} 

WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        U.DisplayName,
        P.OwnerUserId,
        P.LastEditorUserId,
        P.LastEditDate,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS rank
    FROM 
        Posts P
    JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId = 1 AND P.Score > 0
),
BadgeCounts AS (
    SELECT 
        UserId,
        COUNT(DISTINCT Id) AS BadgeCount
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
    RP.CreationDate,
    RP.DisplayName,
    RP.OwnerUserId,
    RP.LastEditorUserId,
    RP.LastEditDate,
    RP.rank,
    COALESCE(BC.BadgeCount, 0) AS BadgeCount,
    CS.CommentCount,
    CS.MaxCommentScore,
    CASE 
        WHEN RP.OwnerUserId IN (SELECT UserId FROM BadgeCounts WHERE BadgeCount >= 3) THEN 'Elite User'
        ELSE 'Regular User'
    END AS UserStatus,
    STRING_AGG(T.TagName, ', ') WITHIN GROUP (ORDER BY T.Count DESC) AS TopTags
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
LEFT JOIN 
    CommentStats CS ON RP.Id = CS.PostId
LEFT JOIN 
    Posts P ON RP.Id = P.Id
LEFT JOIN 
    Tags T ON P.Id = T.ExcerptPostId
LEFT JOIN 
    PostHistory PH ON RP.Id = PH.PostId AND PH.PostHistoryTypeId = 10
WHERE 
    PH.Comment IS NOT NULL AND PH.Text IS NOT NULL
GROUP BY 
    RP.Id, RP.Title, RP.Score, RP.ViewCount, RP.CreationDate, RP.DisplayName, RP.OwnerUserId, RP.LastEditorUserId, RP.LastEditDate, RP.rank, BC.BadgeCount, CS.CommentCount, CS.MaxCommentScore
ORDER BY 
    RP.rank, RP.Score DESC, RP.ViewCount DESC;
