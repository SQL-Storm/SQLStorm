WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.LastActivityDate,
        U.DisplayName AS OwnerDisplayName,
        U.Reputation,
        U.AccountId,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId IN (1, 2) AND P.Score > 0 AND P.ViewCount > 0
),
BadgeCounts AS (
    SELECT 
        B.UserId,
        COUNT(B.Id) AS BadgeCount
    FROM 
        Badges B
    WHERE 
        B.Class = 1 AND B.TagBased = FALSE
    GROUP BY 
        B.UserId
),
CommentMetrics AS (
    SELECT 
        PCH.PostId,
        COUNT(C.Id) AS CommentCount,
        SUM(C.Score) AS TotalCommentScore
    FROM 
        PostHistory PCH
    LEFT JOIN 
        Comments C ON PCH.PostId = C.PostId
    WHERE 
        PCH.PostHistoryTypeId = 1
    GROUP BY 
        PCH.PostId
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.OwnerDisplayName,
    RP.Reputation,
    RP.AccountId,
    RP.Rank,
    BC.BadgeCount,
    CM.CommentCount,
    CM.TotalCommentScore,
    CASE 
        WHEN RP.Score > 100 THEN 'High'
        WHEN RP.Score BETWEEN 50 AND 100 THEN 'Medium'
        ELSE 'Low'
    END AS ScoreTier,
    STRING_AGG(CAST(T.TagName AS VARCHAR), ', ' ORDER BY T.Count DESC) AS TopTags
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.AccountId = BC.UserId
LEFT JOIN 
    CommentMetrics CM ON RP.Id = CM.PostId
LEFT JOIN 
    Tags T ON RP.Id = T.ExcerptPostId
GROUP BY 
    RP.Id, RP.Title, RP.Score, RP.ViewCount, RP.CreationDate, RP.LastActivityDate, RP.OwnerDisplayName, RP.Reputation, RP.AccountId, RP.Rank, BC.BadgeCount, CM.CommentCount, CM.TotalCommentScore
ORDER BY 
    RP.Rank, RP.Score DESC;