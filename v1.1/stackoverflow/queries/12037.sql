WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.OwnerUserId,
        U.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.CreationDate) AS PostRank,
        COUNT(CASE WHEN V.VoteTypeId = 2 THEN 1 END) OVER (PARTITION BY P.Id) AS UpVotes,
        COUNT(CASE WHEN V.VoteTypeId = 3 THEN 1 END) OVER (PARTITION BY P.Id) AS DownVotes,
        COUNT(C.Id) OVER (PARTITION BY P.Id) AS CommentCount,
        P.Tags
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    LEFT JOIN 
        Votes V ON P.Id = V.PostId
    LEFT JOIN 
        Comments C ON P.Id = C.PostId
),
TopUsers AS (
    SELECT 
        U.Id,
        U.DisplayName,
        U.Reputation,
        U.CreationDate,
        COUNT(CASE WHEN B.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN B.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN B.Class = 3 THEN 1 END) AS BronzeBadges,
        ROW_NUMBER() OVER (ORDER BY U.Reputation DESC, U.CreationDate) AS UserRank
    FROM 
        Users U
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id, U.DisplayName, U.Reputation, U.CreationDate
),
TagStats AS (
    SELECT 
        T.TagName,
        COUNT(P.Id) AS PostCount,
        SUM(P.Score) AS TotalScore,
        AVG(P.Score) AS AvgScore
    FROM 
        Tags T
    JOIN 
        Posts P ON POSITION(T.TagName IN P.Tags) > 0
    GROUP BY 
        T.TagName
),
PostHistorySummary AS (
    SELECT 
        PH.PostId,
        COUNT(PH.Id) AS RevisionCount,
        MAX(PH.CreationDate) AS LastRevisionDate
    FROM 
        PostHistory PH
    GROUP BY 
        PH.PostId
)
SELECT 
    RP.Id,
    RP.PostTypeId,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.OwnerUserId,
    RP.OwnerDisplayName,
    RP.PostRank,
    RP.UpVotes,
    RP.DownVotes,
    RP.CommentCount,
    TU.DisplayName AS TopUser,
    TU.Reputation,
    TU.GoldBadges,
    TU.SilverBadges,
    TU.BronzeBadges,
    TU.UserRank,
    TS.TagName,
    TS.PostCount,
    TS.TotalScore,
    TS.AvgScore,
    PHS.RevisionCount,
    PHS.LastRevisionDate
FROM 
    RankedPosts RP
JOIN 
    TopUsers TU ON RP.OwnerUserId = TU.Id AND TU.UserRank <= 10
JOIN 
    TagStats TS ON POSITION(TS.TagName IN RP.Tags) > 0
LEFT JOIN 
    PostHistorySummary PHS ON RP.Id = PHS.PostId
WHERE 
    RP.PostRank <= 50
ORDER BY 
    RP.Score DESC, 
    RP.CreationDate;