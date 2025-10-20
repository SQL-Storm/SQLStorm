-- {"query": "42018.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 816} 

WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.OwnerUserId,
        P.LastActivityDate,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.CreationDate) AS UserPostRank
    FROM 
        Posts P
    WHERE 
        P.PostTypeId IN (1, 2) AND P.Score > 0
),
TopUsers AS (
    SELECT 
        U.Id,
        U.Reputation,
        U.CreationDate,
        U.DisplayName,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        COUNT(DISTINCT CASE WHEN B.Class = 1 THEN B.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN B.Class = 2 THEN B.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN B.Class = 3 THEN B.Id END) AS BronzeBadges
    FROM 
        Users U
    JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id
    HAVING 
        COUNT(DISTINCT B.Id) > 0
),
UserActivity AS (
    SELECT 
        U.Id,
        U.DisplayName,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(DISTINCT V.Id) AS TotalVotes,
        COUNT(DISTINCT PH.Id) AS TotalPostHistory
    FROM 
        Users U
    LEFT JOIN 
        Comments C ON U.Id = C.UserId
    LEFT JOIN 
        Votes V ON U.Id = V.UserId
    LEFT JOIN 
        PostHistory PH ON U.Id = PH.UserId
    GROUP BY 
        U.Id
),
PostTags AS (
    SELECT 
        P.Id,
        UNNEST(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), ''><'')) AS TagName
    FROM 
        Posts P
    WHERE 
        P.PostTypeId = 1
),
TagStats AS (
    SELECT 
        T.TagName,
        COUNT(DISTINCT P.Id) AS QuestionCount,
        AVG(P.Score) AS AvgScore,
        SUM(P.ViewCount) AS TotalViews
    FROM 
        Tags T
    JOIN 
        PostTags PT ON T.TagName = PT.TagName
    JOIN 
        Posts P ON PT.Id = P.Id
    WHERE 
        P.PostTypeId = 1
    GROUP BY 
        T.TagName
)
SELECT 
    TU.Id,
    TU.DisplayName,
    TU.Reputation,
    TU.TotalBadges,
    TU.GoldBadges,
    TU.SilverBadges,
    TU.BronzeBadges,
    UA.TotalComments,
    UA.TotalVotes,
    UA.TotalPostHistory,
    TS.TagName,
    TS.QuestionCount,
    TS.AvgScore,
    TS.TotalViews,
    RP.Id AS TopPostId,
    RP.Score AS TopPostScore,
    RP.ViewCount AS TopPostViews,
    RP.LastActivityDate AS TopPostLastActivity
FROM 
    TopUsers TU
JOIN 
    UserActivity UA ON TU.Id = UA.Id
JOIN 
    RankedPosts RP ON TU.Id = RP.OwnerUserId AND RP.UserPostRank = 1
JOIN 
    PostTags PT ON RP.Id = PT.Id
JOIN 
    TagStats TS ON PT.TagName = TS.TagName
ORDER BY 
    TU.Reputation DESC, 
    RP.Score DESC, 
    TS.TotalViews DESC;
