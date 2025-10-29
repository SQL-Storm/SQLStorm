WITH UserReputationTiers AS (
    SELECT
        Id AS UserId,
        DisplayName,
        Reputation,
        CASE
            WHEN Reputation >= 50000 THEN 'Elite'
            WHEN Reputation >= 10000 THEN 'Expert'
            WHEN Reputation >= 2000 THEN 'Advanced'
            WHEN Reputation >= 500 THEN 'Journeyman'
            ELSE 'Novice'
        END AS ReputationTier,
        CreationDate AS UserCreationDate,
        LastAccessDate
    FROM Users
    WHERE LastAccessDate >= TIMESTAMP '2023-01-01'
),
PostHistoryMetrics AS (
    SELECT
        PH.PostId,
        MIN(PH.CreationDate) AS FirstHistoryEventDate,
        MAX(PH.CreationDate) AS LastHistoryEventDate,
        COUNT(DISTINCT PH.Id) AS TotalHistoryEntries,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS TotalEditCount,
        EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - MAX(PH.CreationDate))) / (60 * 60 * 24) AS DaysSinceLastHistoryEvent,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN 'Closed' ELSE NULL END) AS HasClosedHistory,
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN 'Reopened' ELSE NULL END) AS HasReopenedHistory,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.Comment ELSE NULL END) AS LastCloseReasonId
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 10, 11, 12, 13, 16, 35)
    GROUP BY PH.PostId
),
TagPerformance AS (
    SELECT
        TRIM(SUBSTRING(P.Tags FROM 2 FOR (POSITION('>' IN P.Tags) - 2))) AS PrimaryTag,
        COUNT(P.Id) AS TagQuestionCount,
        AVG(P.Score) AS AvgQuestionScore,
        SUM(COALESCE(P.AnswerCount, 0)) AS TotalAnswersUnderTag,
        SUM(CASE WHEN P.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS TagAcceptedAnswerCount,
        MAX(P.CreationDate) AS LatestQuestionInTag
    FROM Posts P
    WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL
    GROUP BY TRIM(SUBSTRING(P.Tags FROM 2 FOR (POSITION('>' IN P.Tags) - 2)))
    HAVING COUNT(P.Id) > 100
),
UserEngagementSummary AS (
    SELECT
        URT.UserId,
        URT.ReputationTier,
        COUNT(DISTINCT P.Id) AS UserPostsCount,
        SUM(P.Score) AS UserTotalPostScore,
        AVG(P.Score) AS UserAvgPostScore,
        COUNT(DISTINCT C.Id) AS UserCommentCount,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UserTotalUpvotesGiven,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS UserTotalDownvotesGiven,
        MAX(CASE WHEN P.PostTypeId = 1 THEN P.CreationDate ELSE NULL END) AS LatestQuestionDate,
        MAX(CASE WHEN P.PostTypeId = 2 THEN P.CreationDate ELSE NULL END) AS LatestAnswerDate
    FROM UserReputationTiers URT
    LEFT JOIN Posts P ON URT.UserId = P.OwnerUserId
    LEFT JOIN Comments C ON URT.UserId = C.UserId
    LEFT JOIN Votes V ON URT.UserId = V.UserId
    GROUP BY URT.UserId, URT.ReputationTier
),
PostWithDetailedStats AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        PT.Name AS PostTypeName,
        P.Title,
        P.CreationDate AS PostCreationDate,
        P.LastActivityDate,
        P.Score,
        P.ViewCount,
        P.CommentCount,
        P.FavoriteCount,
        P.OwnerUserId,
        COALESCE(URT.DisplayName, 'unknown') AS OwnerDisplayName,
        URT.Reputation AS OwnerReputation,
        URT.ReputationTier AS OwnerReputationTier,
        UES.UserPostsCount AS OwnerTotalPosts,
        UES.UserAvgPostScore AS OwnerAvgPostScore,
        PHM.TotalEditCount,
        PHM.DaysSinceLastHistoryEvent,
        PHM.HasClosedHistory,
        PHM.HasReopenedHistory,
        PHM.LastCloseReasonId,
        COALESCE(P.Tags, '<no-tags>') AS Tags,
        TRIM(SUBSTRING(P.Tags FROM 2 FOR (POSITION('>' IN P.Tags) - 2))) AS PrimaryTag,
        (P.Score + COALESCE(P.FavoriteCount, 0) * 2.5) / NULLIF(P.ViewCount + P.CommentCount * 0.75 + P.AnswerCount * 1.5, 0) AS EngagementRatio,
        DENSE_RANK() OVER (PARTITION BY P.PostTypeId, P.OwnerUserId ORDER BY (P.Score + COALESCE(P.FavoriteCount, 0) * 2.5) / NULLIF(P.ViewCount + P.CommentCount * 0.75 + P.AnswerCount * 1.5, 0) DESC, P.CreationDate DESC) AS OwnerPostEngagementRank,
        LAG(P.Score, 1, 0) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS PreviousPostScore,
        (SELECT COUNT(A.Id) FROM Posts A WHERE A.ParentId = P.Id AND A.PostTypeId = 2) AS QuestionAnswerCount,
        EXISTS (
            SELECT 1 FROM Badges B
            WHERE B.UserId = P.OwnerUserId
              AND B.Name = 'Fanatic'
              AND B.Class = 1
              AND P.PostTypeId = 1
        ) AS HasFanaticBadgeAndIsQuestion,
        COALESCE(EXTRACT(EPOCH FROM (COALESCE(P.LastActivityDate, P.CreationDate) - P.CreationDate)) / 60, 0) AS ActivityDurationMinutes
    FROM Posts P
    INNER JOIN PostTypes PT ON P.PostTypeId = PT.Id
    LEFT JOIN UserReputationTiers URT ON P.OwnerUserId = URT.UserId
    LEFT JOIN UserEngagementSummary UES ON P.OwnerUserId = UES.UserId
    LEFT JOIN PostHistoryMetrics PHM ON P.Id = PHM.PostId
    WHERE P.PostTypeId IN (1, 2)
      AND P.CreationDate >= TIMESTAMP '2022-06-01'
      AND P.OwnerUserId IS NOT NULL
      AND P.Body IS NOT NULL
      AND P.Score > 0
),
HighlyInteractedPosts AS (
    SELECT
        PDS.PostId,
        PDS.Title,
        PDS.PostTypeName,
        PDS.PostCreationDate,
        PDS.Score,
        PDS.ViewCount,
        PDS.CommentCount,
        PDS.FavoriteCount,
        PDS.OwnerDisplayName,
        PDS.OwnerReputation,
        PDS.PrimaryTag,
        PDS.EngagementRatio,
        PDS.TotalEditCount,
        PDS.HasClosedHistory,
        PDS.HasReopenedHistory,
        CR.Name AS CloseReasonName,
        PDS.QuestionAnswerCount,
        PDS.HasFanaticBadgeAndIsQuestion,
        PDS.ActivityDurationMinutes,
        PL.RelatedPostId,
        LOWER(LT.Name) AS LinkTypeName,
        'Score: ' || PDS.Score || ' | Views: ' || COALESCE(PDS.ViewCount, 0) || ' | Comments: ' || PDS.CommentCount AS StatsSummary,
        COALESCE((SELECT U.DisplayName FROM Users U WHERE U.Id = P_orig.LastEditorUserId), 'Community Editor') AS LastEditorDisplayName,
        PDS.OwnerUserId
    FROM PostWithDetailedStats PDS
    LEFT JOIN PostLinks PL ON PDS.PostId = PL.PostId
    LEFT JOIN LinkTypes LT ON PL.LinkTypeId = LT.Id
    LEFT JOIN Posts P_orig ON PDS.PostId = P_orig.Id
    LEFT JOIN CloseReasonTypes CR ON PDS.LastCloseReasonId = CAST(CR.Id AS TEXT)
    WHERE PDS.Score > 75
      AND PDS.ViewCount > 5000
      AND PDS.EngagementRatio > 0.15
      AND PDS.OwnerReputationTier IN ('Expert', 'Elite')
      AND PDS.PrimaryTag IN (SELECT PrimaryTag FROM TagPerformance WHERE AvgQuestionScore > 100 AND TagQuestionCount > 500)
      AND PDS.HasClosedHistory IS NULL
      AND NOT EXISTS (
          SELECT 1 FROM PostLinks PL_dup WHERE PL_dup.RelatedPostId = PDS.PostId AND PL_dup.LinkTypeId = 3
      )
)
SELECT
    HIP.PostId,
    HIP.Title,
    HIP.PostTypeName,
    HIP.PostCreationDate,
    HIP.OwnerDisplayName,
    HIP.OwnerReputation,
    HIP.PrimaryTag,
    HIP.EngagementRatio,
    HIP.TotalEditCount,
    HIP.HasClosedHistory,
    HIP.LinkTypeName,
    HIP.StatsSummary,
    HIP.LastEditorDisplayName,
    HIP.QuestionAnswerCount,
    HIP.HasFanaticBadgeAndIsQuestion,
    HIP.ActivityDurationMinutes,
    (SELECT COUNT(V.Id) FROM Votes V INNER JOIN Users U_v ON V.UserId = U_v.Id WHERE V.PostId = HIP.PostId AND V.VoteTypeId = 2 AND U_v.Reputation > 2000) AS HighRepUpvotes,
    EXISTS (SELECT 1 FROM Comments C WHERE C.PostId = HIP.PostId AND LOWER(C.Text) LIKE '%clarification%') AS HasClarificationComment,
    COALESCE(EXTRACT(DAY FROM (TIMESTAMP '2024-10-01 12:34:56' - HIP.PostCreationDate)), 0) AS DaysSinceCreation,
    HIP.TotalEditCount / NULLIF(HIP.CommentCount, 0) AS EditToCommentRatio,
    AVG(P_full.Score) OVER (PARTITION BY P_full.OwnerUserId ORDER BY P_full.CreationDate ROWS BETWEEN 4 PRECEDING AND CURRENT ROW) AS RollingAvgOwnerScoreQuestions,
    DENSE_RANK() OVER (ORDER BY UES.UserTotalUpvotesGiven DESC) AS GlobalUserUpvoteRank,
    CASE
        WHEN HIP.HasFanaticBadgeAndIsQuestion THEN 'Fanatic Question'
        WHEN HIP.PostTypeName = 'Question' THEN 'Standard Question'
        ELSE 'N/A'
    END AS QuestionBadgeStatusLabel,
    P_Related.Title AS RelatedPostTitle
FROM HighlyInteractedPosts HIP
LEFT JOIN UserEngagementSummary UES ON HIP.OwnerUserId = UES.UserId
LEFT JOIN Posts P_full ON HIP.PostId = P_full.Id AND P_full.PostTypeId = 1
LEFT JOIN Posts P_Related ON HIP.RelatedPostId = P_Related.Id
WHERE HIP.PostTypeName = 'Question'
  AND HIP.ActivityDurationMinutes > 120
  AND NOT EXISTS (
      SELECT 1 FROM Votes V_offensive WHERE V_offensive.PostId = HIP.PostId AND V_offensive.VoteTypeId = 4
  )

UNION ALL

SELECT
    PDS.PostId,
    PDS.Title,
    PDS.PostTypeName,
    PDS.PostCreationDate,
    PDS.OwnerDisplayName,
    PDS.OwnerReputation,
    PDS.PrimaryTag,
    PDS.EngagementRatio,
    PDS.TotalEditCount,
    PDS.HasClosedHistory,
    LOWER(LT.Name) AS LinkTypeName,
    'Score: ' || PDS.Score || ' | Comments: ' || PDS.CommentCount AS StatsSummary,
    COALESCE((SELECT U.DisplayName FROM Users U WHERE U.Id = P_orig_answer.LastEditorUserId), 'System') AS LastEditorDisplayName,
    PDS.QuestionAnswerCount,
    PDS.HasFanaticBadgeAndIsQuestion,
    PDS.ActivityDurationMinutes,
    (SELECT COUNT(V.Id) FROM Votes V INNER JOIN Users U_v ON V.UserId = U_v.Id WHERE V.PostId = PDS.PostId AND V.VoteTypeId = 2 AND U_v.Reputation <= 500) AS LowRepUpvotes,
    FALSE AS HasClarificationComment,
    COALESCE(EXTRACT(DAY FROM (TIMESTAMP '2024-10-01 12:34:56' - PDS.PostCreationDate)), 0) AS DaysSinceCreation,
    PDS.TotalEditCount / NULLIF(PDS.CommentCount, 0) AS EditToCommentRatio,
    AVG(P_orig_answer.Score) OVER (PARTITION BY P_orig_answer.OwnerUserId ORDER BY P_orig_answer.CreationDate ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS RollingAvgOwnerScoreAnswers,
    DENSE_RANK() OVER (ORDER BY UES.UserTotalDownvotesGiven DESC) AS GlobalUserDownvoteRank,
    'Answer Post' AS QuestionBadgeStatusLabel,
    NULL AS RelatedPostTitle
FROM PostWithDetailedStats PDS
INNER JOIN Posts P_orig_answer ON PDS.PostId = P_orig_answer.Id
LEFT JOIN UserEngagementSummary UES ON PDS.OwnerUserId = UES.UserId
LEFT JOIN PostLinks PL ON PDS.PostId = PL.PostId
LEFT JOIN LinkTypes LT ON PL.LinkTypeId = LT.Id
WHERE PDS.PostTypeId = 2
  AND PDS.Score >= 20
  AND PDS.OwnerReputationTier IN ('Novice', 'Journeyman')
  AND PDS.PostCreationDate BETWEEN TIMESTAMP '2023-01-01' AND TIMESTAMP '2023-09-30'
  AND PDS.TotalEditCount < 5
  AND NOT EXISTS (
      SELECT 1 FROM Badges B WHERE B.UserId = PDS.OwnerUserId AND B.Name = 'Critic'
  )
ORDER BY PostCreationDate DESC, EngagementRatio DESC
LIMIT 7500;