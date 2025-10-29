WITH UserMetrics AS (
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        MAX(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS HasGoldBadge,
        COUNT(DISTINCT P.Id) FILTER (WHERE P.PostTypeId = 1) AS TotalQuestionsAsked,
        COUNT(DISTINCT P.Id) FILTER (WHERE P.PostTypeId = 2) AS TotalAnswersGiven,
        SUM(P.Score) FILTER (WHERE P.PostTypeId = 1) AS TotalQuestionScore,
        SUM(P.Score) FILTER (WHERE P.PostTypeId = 2) AS TotalAnswerScore,
        CAST(COALESCE(SUM(P.Score), 0) AS NUMERIC) / NULLIF(COUNT(DISTINCT P.Id), 0) AS AvgPostScore
    FROM Users U
    LEFT JOIN Badges B ON U.Id = B.UserId
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    GROUP BY U.Id, U.Reputation, U.CreationDate, U.Views, U.UpVotes, U.DownVotes
),
PostHistoryAggregates AS (
    SELECT
        PH.PostId,
        COUNT(PH.Id) AS TotalHistoryEvents,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS MajorEditCount,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (10, 12) THEN 1 ELSE 0 END) AS CloseDeleteCount,
        MAX(PH.CreationDate) AS LastHistoryActivityDate
    FROM PostHistory PH
    GROUP BY PH.PostId
),
PostLinkSummary AS (
    SELECT
        PL.PostId,
        COUNT(DISTINCT PL.RelatedPostId) FILTER (WHERE PL.LinkTypeId = 1) AS LinkedPostCount,
        COUNT(DISTINCT PL.RelatedPostId) FILTER (WHERE PL.LinkTypeId = 3) AS DuplicatePostCount
    FROM PostLinks PL
    GROUP BY PL.PostId
),
HighImpactQuestions AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score,
        P.ViewCount,
        P.Title,
        P.Tags,
        P.AcceptedAnswerId,
        UM.Reputation AS OwnerReputation,
        UM.HasGoldBadge AS OwnerHasGoldBadge,
        PHA.MajorEditCount,
        PHA.CloseDeleteCount,
        PLS.LinkedPostCount,
        PLS.DuplicatePostCount,
        COALESCE(P.FavoriteCount, 0) AS FavoriteCount,
        CAST(P.Score AS NUMERIC) / NULLIF(P.ViewCount, 0) AS ScoreToViewRatio,
        COALESCE(P.AnswerCount, 0) AS ActualAnswerCount,
        RANK() OVER (PARTITION BY (CASE WHEN P.Tags LIKE '%<sql>%' THEN 'SQL' WHEN P.Tags LIKE '%<java>%' THEN 'Java' ELSE 'Other' END) ORDER BY P.Score DESC, P.ViewCount DESC) AS RankWithinTagCategory,
        (SELECT COUNT(C.Id)
         FROM Comments C
         JOIN Users CU ON C.UserId = CU.Id
         WHERE C.PostId = P.Id
           AND CU.Reputation > 5000
           AND C.CreationDate BETWEEN P.CreationDate AND (P.CreationDate + INTERVAL '30 days')
        ) AS HighRepCommentCountInitialMonth,
        ARRAY_LENGTH(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags)-2), '><'), 1) AS NumberOfTagsInQuestion,
        'Question' AS RecordType,
        CAST(NULL AS INT) AS ParentPostId,
        CAST(NULL AS INT) AS AcceptedAnswerScore
    FROM Posts P
    JOIN UserMetrics UM ON P.OwnerUserId = UM.UserId
    LEFT JOIN PostHistoryAggregates PHA ON P.Id = PHA.PostId
    LEFT JOIN PostLinkSummary PLS ON P.Id = PLS.PostId
    WHERE P.PostTypeId = 1
      AND P.Score > 10
      AND P.ViewCount > 1000
      AND P.CreationDate BETWEEN DATE '2020-01-01' AND DATE '2023-12-31'
      AND (P.Tags LIKE '%<performance>%' OR P.Tags LIKE '%<optimization>%')
      AND P.ClosedDate IS NULL
),
EliteAnswerContributions AS (
    SELECT
        A.Id AS PostId,
        A.PostTypeId,
        A.OwnerUserId,
        A.CreationDate AS PostCreationDate,
        A.Score,
        CAST(NULL AS INT) AS ViewCount,
        A.Title,
        CAST(NULL AS VARCHAR(4000)) AS Tags,
        CAST(NULL AS INT) AS AcceptedAnswerId,
        UM.Reputation AS OwnerReputation,
        UM.HasGoldBadge AS OwnerHasGoldBadge,
        PHA.MajorEditCount,
        PHA.CloseDeleteCount,
        PLS.LinkedPostCount,
        CAST(NULL AS BIGINT) AS DuplicatePostCount,
        COALESCE(A.FavoriteCount, 0) AS FavoriteCount,
        CAST(NULL AS NUMERIC) AS ScoreToViewRatio,
        CAST(NULL AS INT) AS ActualAnswerCount,
        NTILE(4) OVER (ORDER BY UM.Reputation DESC, A.Score DESC) AS ReputationQuartileRank,
        (SELECT P.Score FROM Posts P WHERE P.Id = A.ParentId AND P.Score > 50 AND P.AcceptedAnswerId = A.Id) AS AcceptedAnswerForHighScoreQuestionScore,
        CAST(NULL AS INT) AS NumberOfTagsInQuestion,
        'Answer' AS RecordType,
        A.ParentId AS ParentPostId,
        A.Score AS AcceptedAnswerScore
    FROM Posts A
    JOIN UserMetrics UM ON A.OwnerUserId = UM.UserId
    LEFT JOIN PostHistoryAggregates PHA ON A.Id = PHA.PostId
    LEFT JOIN PostLinkSummary PLS ON A.Id = PLS.PostId
    WHERE A.PostTypeId = 2
      AND A.Score > 50
      AND UM.Reputation > 10000
      AND A.CreationDate BETWEEN DATE '2020-01-01' AND DATE '2023-12-31'
      AND A.OwnerUserId IS NOT NULL
)
SELECT
    CombinedResults.PostId,
    CombinedResults.RecordType,
    CombinedResults.OwnerUserId,
    CombinedResults.OwnerReputation,
    CombinedResults.PostCreationDate,
    CombinedResults.Score,
    CombinedResults.ViewCount,
    CombinedResults.Title,
    CombinedResults.Tags,
    CombinedResults.MajorEditCount,
    CombinedResults.CloseDeleteCount,
    CombinedResults.LinkedPostCount,
    CombinedResults.FavoriteCount,
    CombinedResults.ScoreToViewRatio,
    CombinedResults.ActualAnswerCount,
    CombinedResults.NumberOfTagsInQuestion,
    CombinedResults.OwnerHasGoldBadge,
    CombinedResults.ParentPostId,
    CombinedResults.AcceptedAnswerScore,
    FIRST_VALUE(CombinedResults.Title) OVER (PARTITION BY CombinedResults.OwnerUserId ORDER BY CombinedResults.Score DESC, CombinedResults.PostCreationDate DESC) AS TopPostTitleByOwner,
    LAST_VALUE(CombinedResults.PostCreationDate) OVER (PARTITION BY CombinedResults.OwnerUserId ORDER BY CombinedResults.PostCreationDate ASC ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS OwnersFirstRelevantPostDate,
    COALESCE(CombinedResults.Score, 0) * (1 + COALESCE(CombinedResults.LinkedPostCount, 0) + COALESCE(CombinedResults.FavoriteCount, 0))
    / NULLIF(COALESCE(CombinedResults.ViewCount, 1) + COALESCE(CombinedResults.MajorEditCount, 0) + COALESCE(CombinedResults.CloseDeleteCount, 0) + 1, 0) AS EngagementIndex,
    CASE
        WHEN CombinedResults.RecordType = 'Question' AND CombinedResults.Tags IS NOT NULL THEN
            SUBSTRING(CombinedResults.Tags FROM POSITION('<' IN CombinedResults.Tags) + 1 FOR POSITION('>' IN CombinedResults.Tags) - POSITION('<' IN CombinedResults.Tags) - 1)
        WHEN CombinedResults.RecordType = 'Answer' AND CombinedResults.ParentPostId IS NOT NULL THEN
            'Answer_to_Q_' || CAST(CombinedResults.ParentPostId AS TEXT)
        ELSE 'N/A'
    END AS PrimaryTagOrAnswerMarker,
    ( (CombinedResults.PostCreationDate > (CAST(DATE '2024-10-01' AS DATE) - INTERVAL '6 months') AND CombinedResults.Score > 50)
      OR
      (CombinedResults.ViewCount IS NOT NULL AND CombinedResults.ViewCount > 5000 AND (CombinedResults.FavoriteCount > 10 OR CombinedResults.LinkedPostCount > 2))
    ) AS IsTrending,
    (SELECT COUNT(P2.Id) FROM Posts P2 LEFT JOIN PostLinkSummary PLS_sub2 ON P2.Id = PLS_sub2.PostId WHERE P2.OwnerUserId = CombinedResults.OwnerUserId AND COALESCE(PLS_sub2.LinkedPostCount, 0) > COALESCE(CombinedResults.LinkedPostCount, 0)) AS MoreLinkedPostsBySameUser
FROM (
    SELECT
        HIQ.PostId, HIQ.PostTypeId, HIQ.OwnerUserId, HIQ.PostCreationDate, HIQ.Score, HIQ.ViewCount, HIQ.Title, HIQ.Tags, HIQ.AcceptedAnswerId,
        HIQ.OwnerReputation, HIQ.OwnerHasGoldBadge, HIQ.MajorEditCount, HIQ.CloseDeleteCount, HIQ.LinkedPostCount, HIQ.DuplicatePostCount, HIQ.FavoriteCount,
        HIQ.ScoreToViewRatio, HIQ.ActualAnswerCount, HIQ.RankWithinTagCategory AS SpecificRank, HIQ.HighRepCommentCountInitialMonth AS SpecificMetric,
        HIQ.NumberOfTagsInQuestion, HIQ.RecordType, HIQ.ParentPostId, HIQ.AcceptedAnswerScore
    FROM HighImpactQuestions HIQ

    UNION ALL

    SELECT
        EAC.PostId, EAC.PostTypeId, EAC.OwnerUserId, EAC.PostCreationDate, EAC.Score, EAC.ViewCount, EAC.Title, EAC.Tags, EAC.AcceptedAnswerId,
        EAC.OwnerReputation, EAC.OwnerHasGoldBadge, EAC.MajorEditCount, EAC.CloseDeleteCount, EAC.LinkedPostCount, EAC.DuplicatePostCount, EAC.FavoriteCount,
        EAC.ScoreToViewRatio, EAC.ActualAnswerCount, EAC.ReputationQuartileRank AS SpecificRank, EAC.AcceptedAnswerForHighScoreQuestionScore AS SpecificMetric,
        EAC.NumberOfTagsInQuestion, EAC.RecordType, EAC.ParentPostId, EAC.AcceptedAnswerScore
    FROM EliteAnswerContributions EAC
) AS CombinedResults
WHERE
    (COALESCE(CombinedResults.Score, 0) * (1 + COALESCE(CombinedResults.LinkedPostCount, 0) + COALESCE(CombinedResults.FavoriteCount, 0))
     / NULLIF(COALESCE(CombinedResults.ViewCount, 1) + COALESCE(CombinedResults.MajorEditCount, 0) + COALESCE(CombinedResults.CloseDeleteCount, 0) + 1, 0)) IS NOT NULL
    AND (COALESCE(CombinedResults.Score, 0) * (1 + COALESCE(CombinedResults.LinkedPostCount, 0) + COALESCE(CombinedResults.FavoriteCount, 0))
     / NULLIF(COALESCE(CombinedResults.ViewCount, 1) + COALESCE(CombinedResults.MajorEditCount, 0) + COALESCE(CombinedResults.CloseDeleteCount, 0) + 1, 0)) > 0
ORDER BY CombinedResults.OwnerReputation DESC, CombinedResults.Score DESC, EngagementIndex DESC
LIMIT 500;