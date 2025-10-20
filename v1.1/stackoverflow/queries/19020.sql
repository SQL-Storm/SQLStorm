WITH UserActivity AS (
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COALESCE(SUM(P.Score), 0) AS TotalPostScore,
        COALESCE(AVG(CASE WHEN P.PostTypeId = 1 THEN P.Score END), 0.0) AS AvgQuestionScore,
        COALESCE(MAX(B.Class), 4) AS MaxBadgeClass,
        CASE
            WHEN U.Reputation >= 10000 THEN 'Legend'
            WHEN U.Reputation >= 5000 THEN 'Veteran'
            WHEN U.Reputation >= 1000 THEN 'Expert'
            WHEN U.Reputation >= 200 THEN 'Contributor'
            ELSE 'Novice'
        END AS UserTier
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.Reputation, U.CreationDate
    HAVING COUNT(DISTINCT P.Id) > 0 OR COUNT(DISTINCT C.Id) > 0
),
PostEventTimelines AS (
    SELECT
        PH.PostId,
        PH.PostHistoryTypeId,
        PH.CreationDate AS EventDate,
        LAG(PH.CreationDate, 1, PH.CreationDate) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS PreviousEventDate,
        PH.UserId AS EventUserId,
        PH.Comment AS EventComment,
        PH.Text AS EventText,
        ROW_NUMBER() OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS EventSequenceNum
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (1,2,5,10,11,12,13,35,36)
),
AggregatedPostDetails AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.FavoriteCount,
        P.OwnerUserId,
        P.LastEditorUserId,
        P.LastActivityDate,
        P.ClosedDate,
        P.AcceptedAnswerId,
        P.Title,
        P.Body,
        P.Tags,
        CASE WHEN P.Tags IS NOT NULL THEN
            regexp_split_to_array(substring(P.Tags FROM 2 FOR (length(P.Tags) - 2)), '><')
        ELSE NULL END AS TagArray,
        COALESCE(COUNT(DISTINCT C.Id), 0) AS TotalCommentsOnPost,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived,
        MAX(CASE WHEN PL.LinkTypeId = 1 THEN 1 ELSE 0 END) AS HasLinkedPosts,
        MAX(CASE WHEN PL.LinkTypeId = 3 THEN 1 ELSE 0 END) AS HasDuplicatePosts,
        (P.Score * 0.7) + (COALESCE(P.FavoriteCount, 0) * 1.2) + (COALESCE(COUNT(DISTINCT C.Id), 0) * 0.5) AS EngagementScore,
        COALESCE(CAST(P.ViewCount AS NUMERIC) / NULLIF(P.AnswerCount, 0), P.ViewCount) AS ViewToAnswerRatio
    FROM Posts P
    LEFT JOIN Comments C ON P.Id = C.PostId
    LEFT JOIN Votes V ON P.Id = V.PostId
    LEFT JOIN PostLinks PL ON P.Id = PL.PostId OR P.Id = PL.RelatedPostId
    WHERE P.PostTypeId IN (1, 2)
    GROUP BY P.Id, P.PostTypeId, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount,
             P.FavoriteCount, P.OwnerUserId, P.LastEditorUserId, P.LastActivityDate, P.ClosedDate,
             P.AcceptedAnswerId, P.Title, P.Body, P.Tags
),
RankedPosts AS (
    SELECT
        APD.PostId,
        APD.PostTypeId,
        APD.PostCreationDate,
        APD.Score,
        APD.ViewCount,
        APD.AnswerCount,
        APD.FavoriteCount,
        APD.OwnerUserId,
        APD.LastEditorUserId,
        APD.LastActivityDate,
        APD.ClosedDate,
        APD.AcceptedAnswerId,
        APD.Title,
        APD.Body,
        APD.Tags,
        APD.TagArray,
        APD.TotalCommentsOnPost,
        APD.UpvotesReceived,
        APD.DownvotesReceived,
        APD.HasLinkedPosts,
        APD.HasDuplicatePosts,
        APD.EngagementScore,
        APD.ViewToAnswerRatio,
        UA.Reputation AS OwnerReputation,
        UA.UserTier AS OwnerUserTier,
        UA.MaxBadgeClass AS OwnerMaxBadgeClass,
        EXISTS (
            SELECT 1 FROM Badges B_corr
            WHERE B_corr.UserId = APD.OwnerUserId AND B_corr.Class = 1
        ) AS OwnerHasGoldBadge,
        (
            SELECT PH_corr.Comment
            FROM PostHistory PH_corr
            WHERE PH_corr.PostId = APD.PostId
              AND PH_corr.UserId = APD.LastEditorUserId
              AND PH_corr.PostHistoryTypeId IN (4, 5, 6)
            ORDER BY PH_corr.CreationDate DESC
            LIMIT 1
        ) AS LastEditorComment,
        RANK() OVER (PARTITION BY APD.PostTypeId ORDER BY APD.EngagementScore DESC, APD.ViewCount DESC) AS PostEngagementRank,
        AVG(APD.EngagementScore) OVER (PARTITION BY UA.UserTier) AS AvgEngagementScoreForTier,
        (
            (CASE WHEN APD.Title IS NOT NULL THEN lower(APD.Title) END) LIKE '%help%' OR
            (CASE WHEN APD.Title IS NOT NULL THEN lower(APD.Title) END) LIKE '%urgent%' OR
            (CASE WHEN APD.Title IS NOT NULL THEN lower(APD.Title) END) LIKE '%problem%' OR
            (CASE WHEN APD.Title IS NOT NULL THEN lower(APD.Title) END) LIKE '%issue%' OR
            (CASE WHEN APD.Title IS NOT NULL THEN lower(APD.Title) END) LIKE '%how to%'
        ) AS IsProblematicTitle,
        (APD.PostTypeId = 1 AND APD.AcceptedAnswerId IS NULL AND APD.AnswerCount = 0 AND APD.ClosedDate IS NULL AND APD.PostCreationDate < (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30 days')) AS IsStaleUnansweredQuestion,
        EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - APD.LastActivityDate)) / 86400 AS DaysSinceLastActivity,
        COALESCE(APD.TagArray[1], 'no-tag') AS PrimaryTag,
        EXISTS (
            SELECT 1 FROM PostEventTimelines PET_closed
            WHERE PET_closed.PostId = APD.PostId AND PET_closed.PostHistoryTypeId = 10
        ) AND EXISTS (
            SELECT 1 FROM PostEventTimelines PET_reopened
            WHERE PET_reopened.PostId = APD.PostId AND PET_reopened.PostHistoryTypeId = 11
        ) AS WasClosedAndReopened
    FROM AggregatedPostDetails APD
    LEFT JOIN UserActivity UA ON APD.OwnerUserId = UA.UserId
    WHERE APD.PostCreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '2 years')
      AND APD.Score >= 0
),
ClosedPostsAnalysis AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.Title,
        P.OwnerUserId,
        CR.Name AS CloseReason,
        PH.CreationDate AS ClosureDate,
        (
            SELECT MAX(U_closer.Reputation)
            FROM PostHistory PH_closer
            INNER JOIN Users U_closer ON PH_closer.UserId = U_closer.Id
            WHERE PH_closer.PostId = P.Id
              AND PH_closer.PostHistoryTypeId = 10
            GROUP BY PH_closer.PostId
        ) AS MaxCloserReputation,
        (LOWER(CR.Name) LIKE '%duplicate%' OR PH.Comment = '101') AS IsDuplicateClosure,
        'Closed Analysis' AS ReportType
    FROM Posts P
    INNER JOIN PostHistory PH ON P.Id = PH.PostId
    INNER JOIN CloseReasonTypes CR ON CAST(PH.Comment AS SMALLINT) = CR.Id
    WHERE PH.PostHistoryTypeId = 10
      AND P.ClosedDate IS NOT NULL
      AND P.CreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '3 years')
)
SELECT
    RP.PostId,
    RP.PostTypeId,
    RP.Title,
    RP.OwnerUserId,
    U_Owner.DisplayName AS OwnerDisplayName,
    RP.OwnerReputation,
    RP.OwnerUserTier,
    RP.OwnerHasGoldBadge,
    RP.PostCreationDate,
    RP.LastActivityDate,
    RP.ClosedDate,
    RP.Score,
    RP.ViewCount,
    RP.AnswerCount,
    RP.TotalCommentsOnPost,
    RP.UpvotesReceived,
    RP.DownvotesReceived,
    RP.EngagementScore,
    RP.PostEngagementRank,
    RP.AvgEngagementScoreForTier,
    RP.IsProblematicTitle,
    RP.IsStaleUnansweredQuestion,
    RP.DaysSinceLastActivity,
    RP.PrimaryTag,
    RP.LastEditorUserId,
    U_LastEditor.DisplayName AS LastEditorDisplayName,
    RP.LastEditorComment,
    RP.HasLinkedPosts,
    RP.HasDuplicatePosts,
    RP.WasClosedAndReopened,
    'Engaged Post Analysis' AS ReportType,
    NULL AS CloseReason,
    NULL AS MaxCloserReputation,
    RP.TagArray
FROM RankedPosts RP
LEFT JOIN Users U_Owner ON RP.OwnerUserId = U_Owner.Id
LEFT JOIN Users U_LastEditor ON RP.LastEditorUserId = U_LastEditor.Id
WHERE RP.PostEngagementRank <= 100
  AND RP.EngagementScore > 5
  AND RP.DaysSinceLastActivity IS NOT NULL
  AND (RP.OwnerUserTier != 'Novice' OR RP.OwnerHasGoldBadge)
  AND RP.TagArray IS NOT NULL AND array_length(RP.TagArray, 1) > 0
  AND NOT EXISTS (
        SELECT 1 FROM Tags T_corr
        WHERE T_corr.TagName = ANY(RP.TagArray) AND T_corr.IsModeratorOnly = TRUE
  )

UNION ALL

SELECT
    CPA.PostId,
    CPA.PostTypeId,
    CPA.Title,
    CPA.OwnerUserId,
    U_Owner_CPA.DisplayName AS OwnerDisplayName,
    NULL AS OwnerReputation,
    NULL AS OwnerUserTier,
    NULL AS OwnerHasGoldBadge,
    NULL AS PostCreationDate,
    NULL AS LastActivityDate,
    CPA.ClosureDate AS ClosedDate,
    NULL AS Score,
    NULL AS ViewCount,
    NULL AS AnswerCount,
    NULL AS TotalCommentsOnPost,
    NULL AS UpvotesReceived,
    NULL AS DownvotesReceived,
    NULL AS EngagementScore,
    NULL AS PostEngagementRank,
    NULL AS AvgEngagementScoreForTier,
    NULL AS IsProblematicTitle,
    NULL AS IsStaleUnansweredQuestion,
    NULL AS DaysSinceLastActivity,
    NULL AS PrimaryTag,
    NULL AS LastEditorUserId,
    NULL AS LastEditorDisplayName,
    NULL AS LastEditorComment,
    NULL AS HasLinkedPosts,
    NULL AS HasDuplicatePosts,
    NULL AS WasClosedAndReopened,
    CPA.ReportType,
    CPA.CloseReason,
    CPA.MaxCloserReputation,
    NULL AS TagArray
FROM ClosedPostsAnalysis CPA
LEFT JOIN Users U_Owner_CPA ON CPA.OwnerUserId = U_Owner_CPA.Id
WHERE CPA.IsDuplicateClosure = TRUE
  AND CPA.MaxCloserReputation >= 10000
  AND NOT EXISTS (
        SELECT 1 FROM PostHistory PH_reopen_corr
        WHERE PH_reopen_corr.PostId = CPA.PostId AND PH_reopen_corr.PostHistoryTypeId = 11
  );