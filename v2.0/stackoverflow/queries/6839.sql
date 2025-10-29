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
        U.LastAccessDate,
        U.Location,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS rank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId = 1 AND P.ViewCount > 1000 AND P.Score > 0
),
BadgeCounts AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        COUNT(B.Id) AS BadgeCount
    FROM 
        Users U
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    WHERE 
        B.Class = 1 AND B.TagBased = FALSE
    GROUP BY 
        U.Id, U.DisplayName
),
CommentStats AS (
    SELECT 
        P.Id AS PostId,
        COUNT(C.Id) AS CommentCount,
        COALESCE(SUM(C.Score), 0) AS TotalCommentScore
    FROM 
        Posts P
    LEFT JOIN 
        Comments C ON P.Id = C.PostId
    GROUP BY 
        P.Id
),
AvgScores AS (
    SELECT AVG(Score) AS avg_score
    FROM Posts
    WHERE PostTypeId = 1
)
SELECT 
    RP.Id AS PostId,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.rank,
    U.DisplayName AS OwnerDisplayName,
    U.Reputation,
    U.Location,
    COALESCE(B.BadgeCount, 0) AS BadgeCount,
    COALESCE(CS.CommentCount, 0) AS CommentCount,
    COALESCE(CS.TotalCommentScore, 0) AS TotalCommentScore,
    CASE 
        WHEN RP.Score > A.avg_score THEN 'High Scoring'
        WHEN RP.Score < A.avg_score THEN 'Low Scoring'
        ELSE 'Average'
    END AS ScoreTier
FROM 
    RankedPosts RP
LEFT JOIN 
    Users U ON RP.OwnerUserId = U.Id
LEFT JOIN 
    BadgeCounts B ON RP.OwnerUserId = B.UserId
LEFT JOIN 
    CommentStats CS ON RP.Id = CS.PostId
CROSS JOIN
    AvgScores A
WHERE 
    RP.rank <= 10
ORDER BY 
    RP.Score DESC, RP.ViewCount DESC;