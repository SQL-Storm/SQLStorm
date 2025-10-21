-- {"query": "42076.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 878} 

WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.OwnerUserId,
        P.LastActivityDate,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.LastActivityDate DESC) AS UserPostRank
    FROM 
        Posts P
    WHERE 
        P.PostTypeId IN (1, 2)
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
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id
    HAVING 
        COUNT(DISTINCT B.Id) > 0
    ORDER BY 
        U.Reputation DESC
    LIMIT 100
),
UserActivity AS (
    SELECT 
        U.Id,
        U.DisplayName,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(P.Score) AS TotalScore,
        SUM(P.ViewCount) AS TotalViews
    FROM 
        Users U
    JOIN 
        Posts P ON U.Id = P.OwnerUserId
    WHERE 
        U.Id IN (SELECT Id FROM TopUsers)
    GROUP BY 
        U.Id, U.DisplayName
),
PostHistorySummary AS (
    SELECT 
        PH.PostId,
        COUNT(DISTINCT PH.Id) AS TotalEdits,
        MAX(CASE WHEN PH.PostHistoryTypeId = 5 THEN PH.CreationDate END) AS LastEditDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate END) AS LastCloseDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.CreationDate END) AS LastReopenDate
    FROM 
        PostHistory PH
    GROUP BY 
        PH.PostId
),
PostTags AS (
    SELECT 
        P.Id,
        STRING_AGG(T.TagName, ', ') AS Tags
    FROM 
        Posts P
    JOIN 
        LATERAL REGEXP_SPLIT_TO_TABLE(P.Tags, ''><'') AS Tag ON TRUE
    JOIN 
        Tags T ON Tag.TagName = T.TagName
    WHERE 
        P.PostTypeId IN (1, 2)
    GROUP BY 
        P.Id
)
SELECT 
    RP.Id,
    RP.PostTypeId,
    RP.CreationDate,
    RP.Score,
    RP.ViewCount,
    RP.OwnerUserId,
    RP.LastActivityDate,
    RP.UserPostRank,
    UA.DisplayName,
    UA.TotalPosts,
    UA.TotalQuestions,
    UA.TotalAnswers,
    UA.TotalScore,
    UA.TotalViews,
    PHS.TotalEdits,
    PHS.LastEditDate,
    PHS.LastCloseDate,
    PHS.LastReopenDate,
    PT.Tags
FROM 
    RankedPosts RP
JOIN 
    UserActivity UA ON RP.OwnerUserId = UA.Id
LEFT JOIN 
    PostHistorySummary PHS ON RP.Id = PHS.PostId
LEFT JOIN 
    PostTags PT ON RP.Id = PT.Id
WHERE 
    RP.UserPostRank <= 5
ORDER BY 
    RP.OwnerUserId, 
    RP.UserPostRank;
