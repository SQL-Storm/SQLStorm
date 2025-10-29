WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName AS UserName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS AnswersGiven,
        SUM(P.Score) AS TotalPostScore,
        AVG(CASE WHEN P.PostTypeId = 1 THEN P.Score END) AS AvgQuestionScore,
        AVG(CASE WHEN P.PostTypeId = 2 THEN P.Score END) AS AvgAnswerScore,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotesGiven,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotesGiven,
        SUM(CASE WHEN V.VoteTypeId = 1 THEN 1 ELSE 0 END) AS TotalAcceptedAnswersVoted,
        MAX(P.LastActivityDate) AS LastPostActivity,
        MAX(C.CreationDate) AS LastCommentActivity
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V ON U.Id = V.UserId
    WHERE U.Reputation >= 1000 AND U.Views > 50
      AND U.CreationDate >= TIMESTAMP '2018-01-01'
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
),
PostHistoricalMetrics AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.LastEditDate,
        P.LastActivityDate,
        P.ClosedDate,
        P.AcceptedAnswerId,
        P.Score,
        P.ViewCount,
        P.Tags,
        P.Title,
        (SELECT COUNT(DISTINCT PH.UserId)
         FROM PostHistory PH
         WHERE PH.PostId = P.Id
           AND PH.PostHistoryTypeId IN (4, 5, 6, 8, 9)) AS UniqueEditorsCount,
        (SELECT SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END)
         FROM PostHistory PH
         WHERE PH.PostId = P.Id) AS TotalContentEdits,
        (SELECT MAX(PH.CreationDate)
         FROM PostHistory PH
         WHERE PH.PostId = P.Id AND PH.PostHistoryTypeId IN (4, 5, 6)) AS LastContentEditDate,
        COALESCE(
            (SELECT CR.Name
             FROM PostHistory PH_Close
             JOIN CloseReasonTypes CR ON CAST(PH_Close.Comment AS SMALLINT) = CR.Id
             WHERE PH_Close.PostId = P.Id
               AND PH_Close.PostHistoryTypeId = 10
             ORDER BY PH_Close.CreationDate DESC
             LIMIT 1), 'N/A') AS LastCloseReason,
        COALESCE(P.LastEditorDisplayName, (SELECT U_LE.DisplayName FROM Users U_LE WHERE U_LE.Id = P.LastEditorUserId), 'Community/Unknown') AS ActualLastEditorName,
        LENGTH(P.Body) AS InitialBodyLength,
        P.ParentId
    FROM Posts P
    WHERE P.PostTypeId IN (1, 2)
      AND P.CreationDate >= TIMESTAMP '2019-01-01'
),
PostTagAnalysis AS (
    SELECT
        PHM.PostId,
        PHM.OwnerUserId,
        LOWER(TRIM(UNNEST(string_to_array(SUBSTRING(PHM.Tags, 2, LENGTH(PHM.Tags) - 2), '><')))) AS TagName
    FROM PostHistoricalMetrics PHM
    WHERE PHM.Tags IS NOT NULL AND LENGTH(PHM.Tags) > 2
),
PostLinkSummary AS (
    SELECT
        PL.PostId,
        COUNT(DISTINCT PL.RelatedPostId) AS LinkedPostsCount,
        SUM(CASE WHEN PL.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateLinksCount,
        MAX(P_Related.Score) AS MaxRelatedPostScore,
        AVG(P_Related.Score) AS AvgRelatedPostScore
    FROM PostLinks PL
    JOIN Posts P_Related ON PL.RelatedPostId = P_Related.Id
    GROUP BY PL.PostId
),
UserBadgePerformance AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(B.Date) AS LastBadgeDate
    FROM Badges B
    GROUP BY B.UserId
),
AvgPostScorePerUserWindow AS (
    SELECT
        PHM.PostId,
        PHM.OwnerUserId,
        PHM.Score,
        PHM.PostCreationDate,
        AVG(PHM.Score) OVER (PARTITION BY PHM.OwnerUserId ORDER BY PHM.PostCreationDate) AS RunningAvgScoreForUser,
        LAG(PHM.Score, 1, 0) OVER (PARTITION BY PHM.OwnerUserId ORDER BY PHM.PostCreationDate) AS PreviousPostScore,
        NTH_VALUE(PHM.Title, 1) OVER (PARTITION BY PHM.OwnerUserId ORDER BY PHM.Score DESC) AS HighestScoredPostTitleByOwner
    FROM PostHistoricalMetrics PHM
),
RankedUsers AS (
    SELECT
        UE.UserId,
        UE.UserName,
        UE.Reputation,
        UE.UserCreationDate,
        UE.LastAccessDate,
        UE.TotalPosts,
        UE.QuestionsAsked,
        UE.AnswersGiven,
        UE.TotalPostScore,
        UE.AvgQuestionScore,
        UE.AvgAnswerScore,
        UE.TotalCommentsMade,
        UE.TotalUpVotesGiven,
        UE.TotalDownVotesGiven,
        UE.TotalAcceptedAnswersVoted,
        UE.LastPostActivity,
        UE.LastCommentActivity,
        UBP.TotalBadges,
        UBP.GoldBadges,
        UBP.SilverBadges,
        UBP.BronzeBadges,
        UBP.LastBadgeDate,
        RANK() OVER (ORDER BY UE.Reputation DESC, UE.UserCreationDate ASC) AS GlobalReputationRank,
        NTILE(10) OVER (ORDER BY UE.TotalPosts DESC) AS PostCountDecile
    FROM UserEngagement UE
    LEFT JOIN UserBadgePerformance UBP ON UE.UserId = UBP.UserId
    WHERE (UBP.TotalBadges > 5 OR UBP.TotalBadges IS NULL)
    AND UE.LastAccessDate >= TIMESTAMP '2022-01-01'
)
SELECT
    RU.UserId,
    RU.UserName,
    RU.Reputation,
    RU.GlobalReputationRank,
    RU.PostCountDecile,
    'Question Data' AS DataType,
    PHM.PostId,
    PHM.Title AS PostTitle,
    PHM.Score AS PostScore,
    PHM.ViewCount,
    PHM.PostTypeId,
    PHM.PostCreationDate,
    PHM.LastContentEditDate,
    DATE_PART('day', PHM.LastActivityDate - PHM.PostCreationDate) AS PostAgeDays,
    COALESCE(PHM.ActualLastEditorName, 'System/Community') AS LastEditorDetails,
    PHM.UniqueEditorsCount,
    PHM.TotalContentEdits,
    PHM.LastCloseReason,
    ALS.RunningAvgScoreForUser,
    ALS.PreviousPostScore,
    ALS.HighestScoredPostTitleByOwner,
    PLS.LinkedPostsCount,
    PLS.DuplicateLinksCount,
    PLS.MaxRelatedPostScore,
    PLS.AvgRelatedPostScore,
    STRING_AGG(PTA.TagName, ', ') FILTER (WHERE PTA.TagName IS NOT NULL) AS AssociatedTags,
    (SELECT COUNT(DISTINCT v_inner.UserId) FROM Votes v_inner WHERE v_inner.PostId = PHM.PostId AND v_inner.VoteTypeId = 5) AS TotalFavoritesOnPost,
    (CASE
        WHEN PHM.AcceptedAnswerId IS NOT NULL AND PHM.PostTypeId = 1 THEN 'Has Accepted Answer'
        WHEN PHM.ClosedDate IS NOT NULL THEN 'Closed Question'
        WHEN PHM.PostTypeId = 1 AND PHM.ViewCount > 5000 AND PHM.Score > 50 THEN 'High Impact Question'
        WHEN PHM.PostTypeId = 1 AND PHM.InitialBodyLength < 100 THEN 'Short Question'
        ELSE 'Other'
    END) AS PostImpactCategory,
    COALESCE(NULLIF(ROUND(PHM.Score * 1.0 / NULLIF(PHM.ViewCount, 0), 4), 0), 0) AS ScorePerViewRatio,
    (PHM.TotalContentEdits * 1.0 / NULLIF(DATE_PART('day', (TIMESTAMP '2024-10-01 12:34:56') - PHM.PostCreationDate), 0)) AS EditsPerDayRatio
FROM RankedUsers RU
JOIN PostHistoricalMetrics PHM ON RU.UserId = PHM.OwnerUserId
LEFT JOIN PostLinkSummary PLS ON PHM.PostId = PLS.PostId
LEFT JOIN PostTagAnalysis PTA ON PHM.PostId = PTA.PostId
LEFT JOIN AvgPostScorePerUserWindow ALS ON PHM.PostId = ALS.PostId AND RU.UserId = ALS.OwnerUserId
WHERE RU.Reputation > 5000
  AND PHM.PostTypeId = 1
  AND PHM.Score >= 0
  AND (PHM.Tags LIKE '%<sql>%' OR PHM.Tags LIKE '%<database>%' OR PHM.Title ILIKE '%performance%' OR PHM.Title ILIKE '%benchmark%')
  AND PHM.ClosedDate IS NULL
GROUP BY
    RU.UserId, RU.UserName, RU.Reputation, RU.GlobalReputationRank, RU.PostCountDecile,
    PHM.PostId, PHM.Title, PHM.Score, PHM.ViewCount, PHM.PostTypeId, PHM.PostCreationDate, PHM.LastContentEditDate, PHM.LastActivityDate, PHM.ActualLastEditorName, PHM.UniqueEditorsCount, PHM.TotalContentEdits, PHM.LastCloseReason, PHM.AcceptedAnswerId, PHM.ClosedDate, PHM.Tags, PHM.InitialBodyLength,
    PLS.LinkedPostsCount, PLS.DuplicateLinksCount, PLS.MaxRelatedPostScore, PLS.AvgRelatedPostScore,
    ALS.RunningAvgScoreForUser, ALS.PreviousPostScore, ALS.HighestScoredPostTitleByOwner

UNION ALL

SELECT
    RU.UserId,
    RU.UserName,
    RU.Reputation,
    RU.GlobalReputationRank,
    RU.PostCountDecile,
    'Answer Data' AS DataType,
    PHM.PostId,
    PHM.Title AS PostTitle,
    PHM.Score AS PostScore,
    PHM.ViewCount,
    PHM.PostTypeId,
    PHM.PostCreationDate,
    PHM.LastContentEditDate,
    DATE_PART('day', PHM.LastActivityDate - PHM.PostCreationDate) AS PostAgeDays,
    COALESCE(PHM.ActualLastEditorName, 'System/Community') AS LastEditorDetails,
    PHM.UniqueEditorsCount,
    PHM.TotalContentEdits,
    PHM.LastCloseReason,
    ALS.RunningAvgScoreForUser,
    ALS.PreviousPostScore,
    ALS.HighestScoredPostTitleByOwner,
    PLS.LinkedPostsCount,
    PLS.DuplicateLinksCount,
    PLS.MaxRelatedPostScore,
    PLS.AvgRelatedPostScore,
    STRING_AGG(PTA.TagName, ', ') FILTER (WHERE PTA.TagName IS NOT NULL) AS AssociatedTags,
    (SELECT COUNT(DISTINCT v_inner.UserId) FROM Votes v_inner WHERE v_inner.PostId = PHM.PostId AND v_inner.VoteTypeId = 5) AS TotalFavoritesOnPost,
    (CASE
        WHEN P_Parent.AcceptedAnswerId = PHM.PostId THEN 'Accepted Answer'
        WHEN PHM.Score > 20 THEN 'Highly Scored Answer'
        ELSE 'Regular Answer'
    END) AS PostImpactCategory,
    COALESCE(NULLIF(ROUND(PHM.Score * 1.0 / NULLIF(PHM.ViewCount, 0), 4), 0), 0) AS ScorePerViewRatio,
    (PHM.TotalContentEdits * 1.0 / NULLIF(DATE_PART('day', (TIMESTAMP '2024-10-01 12:34:56') - PHM.PostCreationDate), 0)) AS EditsPerDayRatio
FROM RankedUsers RU
JOIN PostHistoricalMetrics PHM ON RU.UserId = PHM.OwnerUserId
JOIN Posts P_Parent ON PHM.ParentId = P_Parent.Id
LEFT JOIN PostLinkSummary PLS ON PHM.PostId = PLS.PostId
LEFT JOIN PostTagAnalysis PTA ON PHM.PostId = PTA.PostId
LEFT JOIN AvgPostScorePerUserWindow ALS ON PHM.PostId = ALS.PostId AND RU.UserId = ALS.OwnerUserId
WHERE RU.Reputation > 2000
  AND COALESCE(RU.SilverBadges, 0) >= 5
  AND PHM.PostTypeId = 2
  AND PHM.Score >= 5
  AND P_Parent.AcceptedAnswerId = PHM.PostId
GROUP BY
    RU.UserId, RU.UserName, RU.Reputation, RU.GlobalReputationRank, RU.PostCountDecile,
    PHM.PostId, PHM.Title, PHM.Score, PHM.ViewCount, PHM.PostTypeId, PHM.PostCreationDate, PHM.LastContentEditDate, PHM.LastActivityDate, PHM.ActualLastEditorName, PHM.UniqueEditorsCount, PHM.TotalContentEdits, PHM.LastCloseReason, PHM.AcceptedAnswerId, PHM.ClosedDate, PHM.Tags, PHM.InitialBodyLength,
    PLS.LinkedPostsCount, PLS.DuplicateLinksCount, PLS.MaxRelatedPostScore, PLS.AvgRelatedPostScore,
    ALS.RunningAvgScoreForUser, ALS.PreviousPostScore, ALS.HighestScoredPostTitleByOwner, P_Parent.AcceptedAnswerId, P_Parent.Id, PHM.ParentId

ORDER BY
    Reputation DESC, UserId, PostScore DESC, PostCreationDate DESC
LIMIT 2000;