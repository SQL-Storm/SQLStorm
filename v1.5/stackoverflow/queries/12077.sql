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
        COUNT(Id) AS PostCount
    FROM 
        RankedPosts
    WHERE 
        UserRank <= 3
    GROUP BY 
        OwnerUserId
),
TagScores AS (
    SELECT 
        T.TagName,
        SUM(P.Score) AS TotalScore,
        COUNT(P.Id) AS PostCount
    FROM 
        Tags T
    JOIN 
        Posts P ON T.WikiPostId = P.Id OR T.ExcerptPostId = P.Id
    GROUP BY 
        T.TagName
),
UserBadgeCounts AS (
    SELECT 
        UserId,
        COUNT(Id) AS BadgeCount
    FROM 
        Badges
    WHERE 
        Class = 1
    GROUP BY 
        UserId
),
PostCommentCounts AS (
    SELECT 
        PostId,
        COUNT(Id) AS CommentCount
    FROM 
        Comments
    GROUP BY 
        PostId
),
PostHistoryCounts AS (
    SELECT 
        PostId,
        COUNT(Id) AS HistoryCount
    FROM 
        PostHistory
    WHERE 
        PostHistoryTypeId IN (4, 5, 6)
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
    TU.MaxScore,
    TU.PostCount,
    TS.TagName,
    TS.TotalScore,
    TS.PostCount AS TagPostCount,
    UBC.BadgeCount,
    PCC.CommentCount,
    PHC.HistoryCount
FROM 
    RankedPosts RP
JOIN 
    TopUsers TU ON RP.OwnerUserId = TU.OwnerUserId
LEFT JOIN 
    TagScores TS ON TS.TagName = (
        SELECT TAGS.TagName
        FROM Tags TAGS
        JOIN Posts P2 ON TAGS.WikiPostId = P2.Id OR TAGS.ExcerptPostId = P2.Id
        WHERE P2.OwnerUserId = RP.OwnerUserId
        ORDER BY P2.Score DESC
        LIMIT 1
    )
LEFT JOIN 
    UserBadgeCounts UBC ON RP.OwnerUserId = UBC.UserId
LEFT JOIN 
    PostCommentCounts PCC ON RP.Id = PCC.PostId
LEFT JOIN 
    PostHistoryCounts PHC ON RP.Id = PHC.PostId
WHERE 
    RP.UserRank = 1
ORDER BY 
    RP.Score DESC, 
    RP.CreationDate;