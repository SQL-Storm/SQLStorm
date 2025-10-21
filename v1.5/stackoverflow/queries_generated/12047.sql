-- {"query": "12047.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 817} 

WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.OwnerUserId,
        U.DisplayName AS OwnerDisplayName,
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
        COUNT(Id) FILTER (WHERE Class = 1) AS GoldBadges,
        COUNT(Id) FILTER (WHERE Class = 2) AS SilverBadges,
        COUNT(Id) FILTER (WHERE Class = 3) AS BronzeBadges
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
    TagStats TS ON RP.Id = ANY(string_to_array(RP.Tags, ''><''))
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
