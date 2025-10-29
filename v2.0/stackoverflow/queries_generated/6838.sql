-- {"query": "6838.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 772} 

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
        P.LastEditorUserId,
        U2.DisplayName AS LastEditorDisplayName,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.ClosedDate,
        P.CommunityOwnedDate,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    LEFT JOIN 
        Users U2 ON P.LastEditorUserId = U2.Id
    WHERE 
        P.PostTypeId IN (1, 2)
        AND P.Score > 0
        AND P.ViewCount > 100
),
BadgeStats AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        COUNT(DISTINCT B.Id) AS BadgeCount,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgeCount,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadgeCount,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgeCount
    FROM 
        Users U
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    WHERE 
        U.Reputation > 100
    GROUP BY 
        U.Id, U.DisplayName
),
CommentMetrics AS (
    SELECT 
        P.Id AS PostId,
        COUNT(C.Id) AS CommentCount,
        MAX(C.Score) AS MaxCommentScore,
        MIN(C.Score) AS MinCommentScore,
        AVG(C.Score) AS AvgCommentScore
    FROM 
        Posts P
    LEFT JOIN 
        Comments C ON P.Id = C.PostId
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
    RP.OwnerDisplayName,
    RP.LastEditorDisplayName,
    RP.AnswerCount,
    RP.CommentCount,
    RP.FavoriteCount,
    RP.ClosedDate,
    RP.CommunityOwnedDate,
    RS.BadgeCount,
    RS.GoldBadgeCount,
    RS.SilverBadgeCount,
    RS.BronzeBadgeCount,
    COALESCE(CM.CommentCount, 0) AS CommentCount,
    COALESCE(CM.MaxCommentScore, 0) AS MaxCommentScore,
    COALESCE(CM.MinCommentScore, 0) AS MinCommentScore,
    COALESCE(CM.AvgCommentScore, 0) AS AvgCommentScore,
    CASE 
        WHEN RP.Rank <= 3 THEN 'Top'
        WHEN RP.Rank <= 10 THEN 'Top 10'
        ELSE 'Other'
    END AS RankStatus
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeStats RS ON RP.OwnerUserId = RS.UserId
LEFT JOIN 
    CommentMetrics CM ON RP.Id = CM.PostId
WHERE 
    RP.Rank <= 10
ORDER BY 
    RP.Score DESC, RP.ViewCount DESC;
