WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.OwnerUserId,
        U.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC) AS UserRank,
        DENSE_RANK() OVER (ORDER BY P.Score DESC) AS ScoreRank
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
        MAX(Score) AS MaxScore,
        COUNT(Id) AS PostCount
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
    WHERE 
        P.PostTypeId = 1
    GROUP BY 
        T.TagName
),
UserActivity AS (
    SELECT 
        U.Id,
        U.DisplayName,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(DISTINCT V.Id) AS TotalVotes,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
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
PostHistorySummary AS (
    SELECT 
        P.Id AS PostId,
        COUNT(DISTINCT PH.Id) AS TotalEdits,
        MAX(CASE WHEN PH.PostHistoryTypeId = 5 THEN PH.CreationDate END) AS LastEditDate
    FROM 
        Posts P
    LEFT JOIN 
        PostHistory PH ON P.Id = PH.PostId
    WHERE 
        P.PostTypeId IN (1, 2)
    GROUP BY 
        P.Id
),
PostTags AS (
    -- derive a post -> most used tag (or tag stats per post) so joins below are valid
    SELECT
        P.Id AS PostId,
        T.TagName,
        COUNT(*) OVER (PARTITION BY P.Id, T.TagName) AS TagCountPerPost
    FROM
        Posts P
    JOIN
        Tags T ON T.WikiPostId = P.Id OR T.ExcerptPostId = P.Id
    WHERE
        P.PostTypeId = 1
)
SELECT 
    U.DisplayName,
    U.Reputation,
    UA.TotalPosts,
    UA.TotalComments,
    UA.TotalVotes,
    UA.UpVotes,
    UA.DownVotes,
    RP.Score AS HighestScore,
    RP.ViewCount AS HighestViewCount,
    RPS.TagName AS MostUsedTag,
    TS.PostCount AS TagPostCount,
    TS.AvgScore AS TagAvgScore,
    PHS.TotalEdits,
    PHS.LastEditDate
FROM 
    RankedPosts RP
JOIN 
    TopUsers TU ON RP.OwnerUserId = TU.OwnerUserId
JOIN 
    Users U ON RP.OwnerUserId = U.Id
JOIN 
    UserActivity UA ON U.Id = UA.Id
LEFT JOIN 
    PostTags RPS ON RP.Id = RPS.PostId
LEFT JOIN
    TagStats TS ON RPS.TagName = TS.TagName
JOIN 
    PostHistorySummary PHS ON RP.Id = PHS.PostId
WHERE 
    RP.UserRank = 1
ORDER BY 
    TU.MaxScore DESC, UA.TotalPosts DESC;