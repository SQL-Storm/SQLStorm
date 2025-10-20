-- {"query": "12013.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 863} 

WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.OwnerUserId,
        U.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.CreationDate) AS UserPostRank,
        DENSE_RANK() OVER (ORDER BY P.Score DESC, P.CreationDate) AS GlobalPostRank
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
        COUNT(*) AS TotalPosts,
        MAX(Score) AS MaxScore,
        SUM(ViewCount) AS TotalViews
    FROM 
        RankedPosts
    WHERE 
        UserPostRank <= 3
    GROUP BY 
        OwnerUserId
    HAVING 
        COUNT(*) >= 3
),
PostHistorySummary AS (
    SELECT 
        PostId,
        COUNT(*) AS TotalEdits,
        MAX(CASE WHEN PostHistoryTypeId = 5 THEN CreationDate END) AS LastEditBodyDate,
        MAX(CASE WHEN PostHistoryTypeId = 6 THEN CreationDate END) AS LastEditTagsDate
    FROM 
        PostHistory
    WHERE 
        PostHistoryTypeId IN (5, 6)
    GROUP BY 
        PostId
),
TagUsage AS (
    SELECT 
        P.Id AS PostId,
        T.TagName,
        COUNT(*) OVER (PARTITION BY T.TagName) AS TagCount
    FROM 
        Posts P
    JOIN 
        string_to_array(P.Tags, ''><'') WITH ORDINALITY AS Tags(TagName, ordinality)
    JOIN 
        Tags T ON Tags.TagName = T.TagName
    WHERE 
        P.PostTypeId = 1
),
CommentActivity AS (
    SELECT 
        C.PostId,
        COUNT(*) AS TotalComments,
        AVG(C.Score) AS AvgCommentScore
    FROM 
        Comments C
    GROUP BY 
        C.PostId
),
UserBadges AS (
    SELECT 
        UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
    FROM 
        Badges
    GROUP BY 
        UserId
)
SELECT 
    RP.Id,
    RP.PostTypeId,
    RP.CreationDate,
    RP.Score,
    RP.ViewCount,
    RP.OwnerUserId,
    RP.OwnerDisplayName,
    RP.UserPostRank,
    RP.GlobalPostRank,
    PHS.TotalEdits,
    PHS.LastEditBodyDate,
    PHS.LastEditTagsDate,
    COALESCE(TU.TagCount, 0) AS TagCount,
    COALESCE(CA.TotalComments, 0) AS TotalComments,
    COALESCE(CA.AvgCommentScore, 0) AS AvgCommentScore,
    COALESCE(UB.GoldBadges, 0) AS GoldBadges,
    COALESCE(UB.SilverBadges, 0) AS SilverBadges,
    COALESCE(UB.BronzeBadges, 0) AS BronzeBadges
FROM 
    RankedPosts RP
LEFT JOIN 
    PostHistorySummary PHS ON RP.Id = PHS.PostId
LEFT JOIN 
    TagUsage TU ON RP.Id = TU.PostId
LEFT JOIN 
    CommentActivity CA ON RP.Id = CA.PostId
LEFT JOIN 
    UserBadges UB ON RP.OwnerUserId = UB.UserId
WHERE 
    RP.OwnerUserId IN (SELECT OwnerUserId FROM TopUsers)
ORDER BY 
    RP.Score DESC, 
    RP.CreationDate;
