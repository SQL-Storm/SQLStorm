WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        COUNT(DISTINCT C.Id) AS TotalComments,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScore,
        SUM(COALESCE(C.Score, 0)) AS TotalCommentScore,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        MAX(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS HasGoldBadge,
        AVG(EXTRACT(EPOCH FROM (P.LastActivityDate - P.CreationDate))) FILTER (WHERE P.Id IS NOT NULL) AS AvgPostActivityDurationSeconds,
        (SELECT COUNT(DISTINCT V.PostId) FROM Votes V WHERE V.UserId = U.Id AND V.VoteTypeId IN (5, 8)) AS BookmarksAndBounties,
        RANK() OVER (ORDER BY U.Reputation DESC, U.CreationDate ASC) AS UserReputationRank
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
),
PostDetailsExtended AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.Title,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.OwnerUserId,
        P.LastActivityDate,
        P.ClosedDate,
        P.LastEditDate,
        (SELECT COUNT(PH_EDITS.Id) FROM PostHistory PH_EDITS WHERE PH_EDITS.PostId = P.Id AND PH_EDITS.PostHistoryTypeId IN (4, 5, 6)) AS EditCount,
        (SELECT MAX(PH_COMMUNITY.CreationDate) FROM PostHistory PH_COMMUNITY WHERE PH_COMMUNITY.PostId = P.Id AND PH_COMMUNITY.PostHistoryTypeId = 16) AS CommunityOwnedDateFromHistory,
        (P.Score * 0.7 + COALESCE(P.ViewCount, 0) * 0.05 + COALESCE(P.AnswerCount, 0) * 0.2 + COALESCE(P.FavoriteCount, 0) * 0.5) AS HotnessScore,
        LAG(P.LastEditDate, 1, P.CreationDate) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS PreviousPostEditDate,
        (
            SELECT ARRAY_AGG(DISTINCT t_val)
            FROM UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><')) AS t(t_val)
            WHERE t_val IS NOT NULL
        ) AS TagArray,
        CASE
            WHEN P.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN P.AcceptedAnswerId IS NOT NULL THEN 'Answered'
            WHEN P.AnswerCount > 0 THEN 'Has Answers'
            ELSE 'Open'
        END AS PostStatus
    FROM Posts P
    WHERE P.PostTypeId = 1
),
AnswerPerformance AS (
    SELECT
        Q.Id AS QuestionId,
        Q.CreationDate AS QuestionCreationDate,
        COUNT(A.Id) AS TotalAnswersReceived,
        SUM(A.Score) AS TotalAnswerScore,
        AVG(A.Score) AS AverageAnswerScore,
        MIN(A.CreationDate) AS FirstAnswerDate,
        MAX(A.CreationDate) AS LastAnswerDate,
        SUM(CASE WHEN A.Id = Q.AcceptedAnswerId THEN A.Score ELSE 0 END) AS AcceptedAnswerScore,
        (SELECT AVG(CASE WHEN V.VoteTypeId = 2 THEN 1.0 ELSE 0.0 END) FROM Votes V WHERE V.PostId = Q.Id AND V.VoteTypeId IN (2,3)) AS UpvoteRatioForQuestion,
        EXTRACT(EPOCH FROM (MIN(A.CreationDate) - Q.CreationDate)) / 3600.0 AS TimeToFirstAnswerHours
    FROM Posts Q
    INNER JOIN Posts A ON Q.Id = A.ParentId
    WHERE Q.PostTypeId = 1 AND A.PostTypeId = 2
    GROUP BY Q.Id, Q.CreationDate, Q.AcceptedAnswerId
),
ModerationActivity AS (
    SELECT
        PH.PostId,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (10, 12, 14) THEN 1 END) AS TotalModerationActions,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate ELSE NULL END) AS LastClosedDate,
        STRING_AGG(DISTINCT CRT.Name, ', ') FILTER (WHERE PH.PostHistoryTypeId = 10) AS CloseReasonNames
    FROM PostHistory PH
    LEFT JOIN CloseReasonTypes CRT ON PH.PostHistoryTypeId = 10 AND PH.Comment = CAST(CRT.Id AS VARCHAR)
    WHERE PH.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20)
    GROUP BY PH.PostId
)
SELECT
    UE.UserId,
    COALESCE(UE.DisplayName, 'Anonymous User') AS UserDisplayName,
    UE.Reputation,
    UE.UserCreationDate,
    UE.TotalQuestions,
    UE.TotalAnswers,
    PDE.PostId,
    PDE.Title,
    PDE.PostCreationDate,
    PDE.PostScore,
    PDE.ViewCount,
    PDE.AnswerCount AS PostAnswerCount,
    PDE.CommentCount AS PostCommentCount,
    PDE.HotnessScore,
    PDE.EditCount,
    PDE.PostStatus,
    AP.TotalAnswersReceived,
    AP.AverageAnswerScore,
    AP.TimeToFirstAnswerHours,
    MA.TotalModerationActions,
    MA.CloseReasonNames,
    COALESCE(PDE.CommunityOwnedDateFromHistory, TIMESTAMP '1900-01-01 00:00:00') AS EffectiveCommunityOwnedDate,
    (
        SELECT SUM(V_BOUNTY.BountyAmount)
        FROM Votes V_BOUNTY
        WHERE V_BOUNTY.PostId = PDE.PostId
          AND V_BOUNTY.VoteTypeId = 8
          AND V_BOUNTY.UserId = UE.UserId
    ) AS BountyStartedByOwner,
    DENSE_RANK() OVER (PARTITION BY UE.UserId ORDER BY PDE.HotnessScore DESC, PDE.PostCreationDate DESC) AS UserPostHotnessRank,
    NTILE(5) OVER (ORDER BY UE.Reputation DESC) AS ReputationQuintile,
    ARRAY_TO_STRING(PDE.TagArray, ', ') AS TagsList,
    LEAD(PDE.PostCreationDate, 1) OVER (PARTITION BY UE.UserId ORDER BY PDE.PostCreationDate) AS NextPostCreationDate,
    (SELECT COUNT(DISTINCT V_FAV.UserId) FROM Votes V_FAV WHERE V_FAV.PostId = PDE.PostId AND V_FAV.VoteTypeId = 5) AS TotalFavoritesOnPost
FROM UserEngagement UE
LEFT JOIN PostDetailsExtended PDE ON UE.UserId = PDE.OwnerUserId
LEFT JOIN AnswerPerformance AP ON PDE.PostId = AP.QuestionId
LEFT JOIN ModerationActivity MA ON PDE.PostId = MA.PostId
WHERE
    UE.Reputation >= 1000
    AND PDE.PostId IS NOT NULL
    AND PDE.PostScore > (
        SELECT AVG(P_inner.Score)
        FROM Posts P_inner
        WHERE P_inner.PostTypeId = 1
          AND P_inner.CreationDate >= (
              SELECT MIN(U_inner.CreationDate)
              FROM Users U_inner
              WHERE U_inner.Reputation >= 1000
          )
    )
    AND PDE.PostCreationDate > (UE.LastAccessDate - INTERVAL '1 year')
    AND LOWER(PDE.Title) LIKE '%sql%'
    AND (
        (PDE.PostStatus = 'Closed' AND MA.TotalModerationActions > 0) OR
        (PDE.PostStatus = 'Answered' AND AP.TimeToFirstAnswerHours < 24 AND AP.AverageAnswerScore > 5) OR
        (PDE.TagArray IS NOT NULL AND EXISTS (
            SELECT 1 FROM UNNEST(PDE.TagArray) AS t(tag) WHERE LOWER(t.tag) IN ('python','javascript')
        ) AND PDE.EditCount > 1 AND PDE.PostScore > 10)
    )
GROUP BY
    UE.UserId,
    UE.DisplayName,
    UE.Reputation,
    UE.UserCreationDate,
    UE.LastAccessDate,
    UE.TotalQuestions,
    UE.TotalAnswers,
    PDE.PostId,
    PDE.Title,
    PDE.PostCreationDate,
    PDE.PostScore,
    PDE.ViewCount,
    PDE.AnswerCount,
    PDE.CommentCount,
    PDE.HotnessScore,
    PDE.EditCount,
    PDE.PostStatus,
    AP.TotalAnswersReceived,
    AP.AverageAnswerScore,
    AP.TimeToFirstAnswerHours,
    MA.TotalModerationActions,
    MA.CloseReasonNames,
    PDE.CommunityOwnedDateFromHistory,
    PDE.TagArray
ORDER BY
    UE.Reputation DESC,
    PDE.HotnessScore DESC,
    PDE.PostCreationDate DESC
LIMIT 1000;