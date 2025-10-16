WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.OwnerUserId,
        U.DisplayName AS OwnerDisplayName,
        P.Tags,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.CreationDate) AS UserPostRank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId IN (1, 2) AND P.Score > 0
),
TopUsers AS (
    SELECT 
        OwnerUserId,
        COUNT(Id) AS TotalPosts,
        SUM(Score) AS TotalScore
    FROM 
        RankedPosts
    WHERE 
        UserPostRank <= 3
    GROUP BY 
        OwnerUserId
    HAVING 
        COUNT(Id) > 1 AND SUM(Score) > 100
),
TagStats AS (
    SELECT 
        T.TagName,
        COUNT(DISTINCT P.Id) AS PostCount,
        AVG(P.Score) AS AvgScore
    FROM 
        Tags T
    JOIN 
        Posts P ON T.WikiPostId = P.Id OR T.ExcerptPostId = P.Id
    WHERE 
        P.PostTypeId = 1
    GROUP BY 
        T.TagName
),
UserBadgeCounts AS (
    SELECT 
        U.Id,
        U.DisplayName,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM 
        Users U
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id, U.DisplayName
),
PostHistorySummary AS (
    SELECT 
        P.Id,
        COUNT(PH.Id) AS TotalEdits,
        MAX(CASE WHEN PH.PostHistoryTypeId = 5 THEN PH.CreationDate END) AS LastEditBodyDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 6 THEN PH.CreationDate END) AS LastEditTagsDate
    FROM 
        Posts P
    LEFT JOIN 
        PostHistory PH ON P.Id = PH.PostId
    WHERE 
        PH.PostHistoryTypeId IN (5, 6)
    GROUP BY 
        P.Id
),
CommentActivity AS (
    SELECT 
        C.PostId,
        COUNT(C.Id) AS TotalComments,
        MAX(C.CreationDate) AS LastCommentDate
    FROM 
        Comments C
    GROUP BY 
        C.PostId
)
SELECT 
    RP.Id,
    RP.PostTypeId,
    RP.CreationDate,
    RP.Score,
    RP.ViewCount,
    RP.OwnerUserId,
    RP.OwnerDisplayName,
    TU.TotalPosts,
    TU.TotalScore,
    TS.TagName,
    TS.PostCount,
    TS.AvgScore,
    UBC.GoldBadges,
    UBC.SilverBadges,
    UBC.BronzeBadges,
    PHS.TotalEdits,
    PHS.LastEditBodyDate,
    PHS.LastEditTagsDate,
    CA.TotalComments,
    CA.LastCommentDate
FROM 
    RankedPosts RP
JOIN 
    TopUsers TU ON RP.OwnerUserId = TU.OwnerUserId
JOIN 
    TagStats TS ON RP.Tags LIKE '%' || TS.TagName || '%'
JOIN 
    UserBadgeCounts UBC ON RP.OwnerUserId = UBC.Id
LEFT JOIN 
    PostHistorySummary PHS ON RP.Id = PHS.Id
LEFT JOIN 
    CommentActivity CA ON RP.Id = CA.PostId
WHERE 
    RP.UserPostRank <= 3
ORDER BY 
    RP.Score DESC, 
    RP.CreationDate;