WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.OwnerUserId,
        P.Tags,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.CreationDate) AS UserPostRank,
        DENSE_RANK() OVER (ORDER BY P.Score DESC, P.CreationDate) AS GlobalPostRank
    FROM 
        Posts P
    WHERE 
        P.PostTypeId IN (1, 2)
),
UserActivity AS (
    SELECT 
        U.Id,
        U.DisplayName,
        U.Reputation,
        U.CreationDate,
        COUNT(DISTINCT P.Id) FILTER (WHERE P.PostTypeId = 1) AS QuestionsAsked,
        COUNT(DISTINCT P.Id) FILTER (WHERE P.PostTypeId = 2) AS AnswersGiven,
        SUM(P.Score) FILTER (WHERE P.PostTypeId = 1) AS TotalQuestionScore,
        SUM(P.Score) FILTER (WHERE P.PostTypeId = 2) AS TotalAnswerScore
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    GROUP BY 
        U.Id, U.DisplayName, U.Reputation, U.CreationDate
),
TagStats AS (
    SELECT 
        T.TagName,
        COUNT(DISTINCT P.Id) AS PostCount,
        SUM(P.Score) AS TotalScore,
        AVG(P.Score) AS AvgScore
    FROM 
        Tags T
    JOIN 
        Posts P ON POSITION('<' || T.TagName || '>' IN P.Tags) > 0
    WHERE 
        P.PostTypeId IN (1, 2)
    GROUP BY 
        T.TagName
),
PostHistorySummary AS (
    SELECT 
        PH.PostId,
        COUNT(DISTINCT PH.Id) AS RevisionCount,
        MAX(PH.CreationDate) AS LastRevisionDate
    FROM 
        PostHistory PH
    WHERE 
        PH.PostHistoryTypeId IN (2, 5, 6)
    GROUP BY 
        PH.PostId
),
UserBadgeCounts AS (
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
    UA.DisplayName,
    UA.Reputation,
    UA.QuestionsAsked,
    UA.AnswersGiven,
    UA.TotalQuestionScore,
    UA.TotalAnswerScore,
    UBC.GoldBadges,
    UBC.SilverBadges,
    UBC.BronzeBadges,
    RP.UserPostRank,
    RP.GlobalPostRank,
    PHS.RevisionCount,
    PHS.LastRevisionDate,
    TS.TagName,
    TS.PostCount,
    TS.TotalScore,
    TS.AvgScore
FROM 
    UserActivity UA
JOIN 
    RankedPosts RP ON UA.Id = RP.OwnerUserId
LEFT JOIN 
    UserBadgeCounts UBC ON UA.Id = UBC.UserId
LEFT JOIN 
    PostHistorySummary PHS ON RP.Id = PHS.PostId
LEFT JOIN 
    LATERAL (
        SELECT 
            TS.TagName,
            TS.PostCount,
            TS.TotalScore,
            TS.AvgScore
        FROM 
            TagStats TS
        WHERE 
            POSITION('<' || TS.TagName || '>' IN RP.Tags) > 0
        ORDER BY 
            TS.TotalScore DESC
        LIMIT 1
    ) TS ON true
WHERE 
    UA.Reputation > 1000
ORDER BY 
    UA.Reputation DESC, 
    UA.QuestionsAsked DESC, 
    UA.AnswersGiven DESC
LIMIT 100;