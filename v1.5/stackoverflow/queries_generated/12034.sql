-- {"query": "12034.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 591} 

WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.OwnerUserId,
        U.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.CreationDate) AS UserRank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId IN (1, 2)
),
TopUsers AS (
    SELECT 
        OwnerUserId,
        MAX(Score) AS MaxScore,
        MAX(ViewCount) AS MaxViewCount
    FROM 
        RankedPosts
    WHERE 
        UserRank = 1
    GROUP BY 
        OwnerUserId
),
UserBadges AS (
    SELECT 
        B.UserId,
        COUNT(CASE WHEN B.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN B.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN B.Class = 3 THEN 1 END) AS BronzeBadges
    FROM 
        Badges B
    GROUP BY 
        B.UserId
),
PostHistorySummary AS (
    SELECT 
        PostId,
        COUNT(CASE WHEN PostHistoryTypeId = 5 THEN 1 END) AS EditCount,
        COUNT(CASE WHEN PostHistoryTypeId IN (10, 11) THEN 1 END) AS CloseReopenCount
    FROM 
        PostHistory
    GROUP BY 
        PostId
),
CommentActivity AS (
    SELECT 
        PostId,
        COUNT(*) AS CommentCount
    FROM 
        Comments
    GROUP BY 
        PostId
)
SELECT 
    RP.Id AS PostId,
    RP.PostTypeId,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.OwnerUserId,
    RP.OwnerDisplayName,
    TU.MaxScore,
    TU.MaxViewCount,
    UB.GoldBadges,
    UB.SilverBadges,
    UB.BronzeBadges,
    PHS.EditCount,
    PHS.CloseReopenCount,
    CA.CommentCount
FROM 
    RankedPosts RP
JOIN 
    TopUsers TU ON RP.OwnerUserId = TU.OwnerUserId
LEFT JOIN 
    UserBadges UB ON RP.OwnerUserId = UB.UserId
LEFT JOIN 
    PostHistorySummary PHS ON RP.Id = PHS.PostId
LEFT JOIN 
    CommentActivity CA ON RP.Id = CA.PostId
WHERE 
    RP.UserRank = 1
ORDER BY 
    RP.Score DESC, 
    RP.CreationDate;
