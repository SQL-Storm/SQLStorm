WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.OwnerUserId,
        U.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.CreationDate) AS UserPostRank,
        P.Tags
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
        SUM(Score) AS TotalScore,
        MAX(ViewCount) AS MaxViewCount
    FROM 
        RankedPosts
    WHERE 
        UserPostRank <= 3
    GROUP BY 
        OwnerUserId
    HAVING 
        COUNT(Id) > 1
),
TagStats AS (
    SELECT 
        T.TagName,
        COUNT(P.Id) AS TagCount,
        AVG(P.Score) AS AvgTagScore
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
        UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
    FROM 
        Badges
    GROUP BY 
        UserId
),
PostHistorySummary AS (
    SELECT 
        PostId,
        COUNT(Id) AS TotalEdits,
        MAX(CASE WHEN PostHistoryTypeId = 1 THEN CreationDate END) AS InitialTitleDate,
        MAX(CASE WHEN PostHistoryTypeId = 2 THEN CreationDate END) AS InitialBodyDate,
        MAX(CASE WHEN PostHistoryTypeId = 5 THEN CreationDate END) AS LastEditBodyDate
    FROM 
        PostHistory
    GROUP BY 
        PostId
),
PostComments AS (
    SELECT 
        PostId,
        COUNT(Id) AS TotalComments,
        AVG(Score) AS AvgCommentScore
    FROM 
        Comments
    GROUP BY 
        PostId
),
-- Explode tags from RankedPosts.Tags into rows in a dialect-neutral way.
RankedPostTags AS (
    SELECT
        RP.Id AS PostId,
        TRIM(tag) AS TagName
    FROM
        RankedPosts RP
    CROSS JOIN LATERAL (
        SELECT regexp_split_to_table(RP.Tags, '><') AS tag
    ) s
    WHERE RP.Tags IS NOT NULL AND RP.Tags <> ''
)
SELECT 
    RP.Id,
    RP.PostTypeId,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.OwnerUserId,
    RP.OwnerDisplayName,
    TU.TotalPosts,
    TU.TotalScore,
    TU.MaxViewCount,
    TS.TagName,
    TS.TagCount,
    TS.AvgTagScore,
    UBC.GoldBadges,
    UBC.SilverBadges,
    UBC.BronzeBadges,
    PHS.TotalEdits,
    PHS.InitialTitleDate,
    PHS.InitialBodyDate,
    PHS.LastEditBodyDate,
    PC.TotalComments,
    PC.AvgCommentScore
FROM 
    RankedPosts RP
JOIN 
    TopUsers TU ON RP.OwnerUserId = TU.OwnerUserId
JOIN 
    RankedPostTags RPT ON RP.Id = RPT.PostId
LEFT JOIN 
    TagStats TS ON RPT.TagName = TS.TagName
LEFT JOIN 
    UserBadgeCounts UBC ON RP.OwnerUserId = UBC.UserId
LEFT JOIN 
    PostHistorySummary PHS ON RP.Id = PHS.PostId
LEFT JOIN 
    PostComments PC ON RP.Id = PC.PostId
WHERE 
    RP.UserPostRank = 1
ORDER BY 
    RP.Score DESC, 
    RP.CreationDate;