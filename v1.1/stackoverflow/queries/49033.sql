WITH UserPostStats AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        COUNT(DISTINCT P_OWNED_Q.Id) AS TotalQuestionsOwned,
        COUNT(DISTINCT P_OWNED_A.Id) AS TotalAnswersWritten,
        SUM(P_OWNED_Q.Score) AS TotalQuestionScore,
        SUM(P_OWNED_Q.ViewCount) AS TotalQuestionViews,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        MAX(U.LastAccessDate) AS LastSeen
    FROM Users U
    LEFT JOIN Posts P_OWNED_Q ON U.Id = P_OWNED_Q.OwnerUserId AND P_OWNED_Q.PostTypeId = 1
    LEFT JOIN Posts P_OWNED_A ON U.Id = P_OWNED_A.OwnerUserId AND P_OWNED_A.PostTypeId = 2
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation
),
UserEditActivity AS (
    SELECT
        PH.UserId,
        COUNT(DISTINCT PH.PostId) AS DistinctPostsEdited,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE 0 END) AS TotalEditsMade
    FROM PostHistory PH
    WHERE PH.UserId IS NOT NULL
    GROUP BY PH.UserId
),
UserBadgeSummary AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges B
    GROUP BY B.UserId
),
PopularTaggedPosts AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.Title
    FROM Posts P
    WHERE P.PostTypeId = 1
      AND P.Score >= 100
      AND P.ViewCount >= 5000
      AND P.Tags IS NOT NULL
      AND EXISTS (
            SELECT 1
            FROM UNNEST(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><')) AS Tag
            WHERE Tag IN ('sql', 'database', 'performance', 'optimization', 'query-optimization', 'indexing')
          )
),
UserPopularStats AS (
    -- Aggregate per user for popular tagged posts; compute median per user using percentile_cont without window (standard aggregate)
    SELECT
        PTP.OwnerUserId AS UserId,
        SUM(PTP.Score) AS TotalScoreFromPopularTaggedQuestions,
        SUM(PTP.ViewCount) AS TotalViewsFromPopularTaggedQuestions,
        COUNT(DISTINCT PTP.PostId) AS NumberOfPopularTaggedQuestionsOwned,
        AVG(PTP.Score) AS AverageScoreOfPopularTaggedQuestions,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY PTP.Score) AS MedianScoreOfPopularTaggedQuestions
    FROM PopularTaggedPosts PTP
    GROUP BY PTP.OwnerUserId
)
SELECT
    UPS.UserId,
    UPS.DisplayName,
    UPS.Reputation,
    UPS.TotalQuestionsOwned,
    UPS.TotalAnswersWritten,
    UPS.TotalCommentsMade,
    COALESCE(UEA.TotalEditsMade, 0) AS TotalEditsMade,
    COALESCE(UBS.GoldBadges, 0) AS GoldBadges,
    COALESCE(UBS.SilverBadges, 0) AS SilverBadges,
    COALESCE(UBS.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(UPS2.TotalScoreFromPopularTaggedQuestions, 0) AS TotalScoreFromPopularTaggedQuestions,
    COALESCE(UPS2.TotalViewsFromPopularTaggedQuestions, 0) AS TotalViewsFromPopularTaggedQuestions,
    COALESCE(UPS2.NumberOfPopularTaggedQuestionsOwned, 0) AS NumberOfPopularTaggedQuestionsOwned,
    UPS2.AverageScoreOfPopularTaggedQuestions,
    UPS2.MedianScoreOfPopularTaggedQuestions,
    UPS.LastSeen
FROM UserPostStats UPS
LEFT JOIN UserEditActivity UEA ON UPS.UserId = UEA.UserId
LEFT JOIN UserBadgeSummary UBS ON UPS.UserId = UBS.UserId
LEFT JOIN UserPopularStats UPS2 ON UPS.UserId = UPS2.UserId
WHERE
    UPS.Reputation >= 50000
    AND COALESCE(UBS.GoldBadges, 0) >= 5
    AND COALESCE(UBS.SilverBadges, 0) >= 20
    AND UPS.TotalQuestionsOwned >= 10
    AND UPS.TotalAnswersWritten >= 50
    AND COALESCE(UEA.TotalEditsMade, 0) >= 50
    AND EXISTS (
        SELECT 1
        FROM PopularTaggedPosts PTP_recent
        WHERE PTP_recent.OwnerUserId = UPS.UserId
          AND PTP_recent.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '3 year')
    )
GROUP BY
    UPS.UserId,
    UPS.DisplayName,
    UPS.Reputation,
    UPS.TotalQuestionsOwned,
    UPS.TotalAnswersWritten,
    UPS.TotalCommentsMade,
    UEA.TotalEditsMade,
    UBS.GoldBadges,
    UBS.SilverBadges,
    UBS.BronzeBadges,
    UPS2.TotalScoreFromPopularTaggedQuestions,
    UPS2.TotalViewsFromPopularTaggedQuestions,
    UPS2.NumberOfPopularTaggedQuestionsOwned,
    UPS2.AverageScoreOfPopularTaggedQuestions,
    UPS2.MedianScoreOfPopularTaggedQuestions,
    UPS.LastSeen
HAVING
    COALESCE(UPS2.NumberOfPopularTaggedQuestionsOwned, 0) >= 5
ORDER BY
    TotalScoreFromPopularTaggedQuestions DESC,
    UPS.Reputation DESC,
    GoldBadges DESC,
    NumberOfPopularTaggedQuestionsOwned DESC
LIMIT 200;