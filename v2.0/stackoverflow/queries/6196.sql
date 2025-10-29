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
        P.PostTypeId IN (1, 2) AND P.Score > 0 AND P.ViewCount > 100
),
BadgeCounts AS (
    SELECT 
        B.UserId,
        COUNT(B.Id) AS BadgeCount
    FROM 
        Badges B
    GROUP BY 
        B.UserId
),
CommentStats AS (
    SELECT 
        P.Id AS PostId,
        COUNT(C.Id) AS CommentCount,
        MAX(C.Score) AS MaxCommentScore
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
    RP.Rank,
    RC.CommentCount,
    RC.MaxCommentScore,
    (RC.CommentCount * RP.Score) AS PostScoreWeight,
    COALESCE(BC.BadgeCount, 0) AS BadgeCount,
    ROW_NUMBER() OVER (ORDER BY RP.Score DESC, RP.ViewCount DESC) AS GlobalRank
FROM 
    RankedPosts RP
LEFT JOIN 
    CommentStats RC ON RP.Id = RC.PostId
LEFT JOIN 
    BadgeCounts BC ON COALESCE(CAST(RP.AccountId AS VARCHAR), RP.OwnerDisplayName) = COALESCE(CAST(BC.UserId AS VARCHAR), CAST(BC.UserId AS VARCHAR))
WHERE 
    EXISTS (
        SELECT 1 
        FROM 
            Votes V
        WHERE 
            V.PostId = RP.Id AND V.VoteTypeId = 2
    )
GROUP BY
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.Rank,
    RC.CommentCount,
    RC.MaxCommentScore,
    BC.BadgeCount,
    RP.AccountId,
    RP.OwnerDisplayName
ORDER BY 
    GlobalRank;