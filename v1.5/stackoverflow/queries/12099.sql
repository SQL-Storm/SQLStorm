WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.OwnerUserId,
        U.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC) AS UserRank,
        DENSE_RANK() OVER (ORDER BY P.Score DESC) AS ScoreRank,
        NTILE(4) OVER (ORDER BY P.CreationDate) AS Quartile
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
        COUNT(Id) AS PostCount,
        SUM(Score) AS TotalScore
    FROM 
        RankedPosts
    WHERE 
        UserRank <= 3
    GROUP BY 
        OwnerUserId
    HAVING 
        COUNT(Id) > 1
),
TagStats AS (
    SELECT 
        T.TagName,
        COUNT(P.Id) AS PostCount,
        AVG(P.Score) AS AvgScore
    FROM 
        Tags T
    JOIN 
        Posts P ON T.WikiPostId = P.Id OR T.ExcerptPostId = P.Id
    GROUP BY 
        T.TagName
),
UserActivity AS (
    SELECT 
        U.Id,
        U.DisplayName,
        COUNT(DISTINCT P.Id) AS PostCount,
        COUNT(DISTINCT C.Id) AS CommentCount,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN 
        Comments C ON U.Id = C.UserId
    LEFT JOIN 
        Votes V ON U.Id = V.UserId
    GROUP BY 
        U.Id, U.DisplayName
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
)
SELECT 
    RP.Id,
    RP.PostTypeId,
    RP.CreationDate,
    RP.Score,
    RP.ViewCount,
    RP.OwnerUserId,
    RP.OwnerDisplayName,
    RP.UserRank,
    RP.ScoreRank,
    RP.Quartile,
    UA.PostCount AS UserPostCount,
    UA.CommentCount AS UserCommentCount,
    UA.UpVoteCount,
    UA.DownVoteCount,
    UB.GoldBadges,
    UB.SilverBadges,
    UB.BronzeBadges,
    TS.TagName,
    TS.PostCount AS TagPostCount,
    TS.AvgScore AS TagAvgScore
FROM 
    RankedPosts RP
JOIN 
    TopUsers TU ON RP.OwnerUserId = TU.OwnerUserId
JOIN 
    UserActivity UA ON RP.OwnerUserId = UA.Id
JOIN 
    UserBadges UB ON RP.OwnerUserId = UB.UserId
LEFT JOIN 
    TagStats TS ON FALSE
WHERE 
    RP.ScoreRank <= 100
ORDER BY 
    RP.Score DESC, RP.CreationDate;