-- {"query": "1996.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2986} 

WITH UserReputationSnapshot AS (
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.DisplayName,
        U.Views AS UserViews,
        U.UpVotes AS UserUpVotes,
        U.DownVotes AS UserDownVotes,
        COUNT(DISTINCT P.Id) AS TotalPostsByOwner,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsByOwner,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScoreReceived,
        COUNT(DISTINCT C.Id) AS TotalCommentsMadeByOwner,
        MAX(P.LastActivityDate) AS LastPostActivityDateByOwner,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS OwnerGoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS OwnerSilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS OwnerBronzeBadges
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.Reputation, U.CreationDate, U.DisplayName, U.Views, U.UpVotes, U.DownVotes
),
PostDetailedMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.ClosedDate,
        P.LastActivityDate,
        P.OwnerUserId,
        P.LastEditorUserId,
        P.AcceptedAnswerId,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6, 8, 9) THEN 1 ELSE 0 END) AS EditCount, -- Edits to Title, Body, Tags
        MAX(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6, 8, 9) THEN PH.CreationDate ELSE NULL END) AS LastUserEditDate,
        COUNT(DISTINCT PH.UserId) AS DistinctEditors,
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseVoteHistoryCount,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate ELSE NULL END) AS FirstCloseVoteDate,
        (SELECT COUNT(DISTINCT V.UserId) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 2) AS UpvoteUsersCount,
        (SELECT COUNT(DISTINCT V.UserId) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 3) AS DownvoteUsersCount
    FROM Posts P
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    GROUP BY
        P.Id, P.PostTypeId, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount, P.CommentCount, P.FavoriteCount,
        P.ClosedDate, P.LastActivityDate, P.OwnerUserId, P.LastEditorUserId, P.AcceptedAnswerId
),
IndividualTagAnalysis AS (
    SELECT
        P.Id AS PostId,
        unnest(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><')) AS TagName
    FROM Posts P
    WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL AND length(P.Tags) > 2
),
PostCommentSummary AS (
    SELECT
        C.PostId,
        COUNT(C.Id) AS TotalComments,
        AVG(C.Score) AS AvgCommentScore,
        MAX(C.CreationDate) AS LatestCommentDate,
        SUM(CASE WHEN C.UserId = PDM.OwnerUserId THEN 1 ELSE 0 END) AS OwnerComments
    FROM Comments C
    JOIN PostDetailedMetrics PDM ON C.PostId = PDM.PostId
    GROUP BY C.PostId
),
QuestionAnswerStats AS (
    SELECT
        Q.Id AS QuestionId,
        COUNT(A.Id) AS TotalAnswers,
        AVG(A.Score) AS AvgAnswerScore,
        MAX(A.CreationDate) AS LatestAnswerDate,
        SUM(CASE WHEN Q.AcceptedAnswerId = A.Id THEN 1 ELSE 0 END) AS HasAcceptedAnswerFlag
    FROM Posts Q
    LEFT JOIN Posts A ON Q.Id = A.ParentId AND A.PostTypeId = 2
    WHERE Q.PostTypeId = 1
    GROUP BY Q.Id
),
LatestPostLink AS (
    SELECT
        PostId,
        RelatedPostId,
        CreationDate AS LinkCreationDate,
        ROW_NUMBER() OVER (PARTITION BY PostId ORDER BY CreationDate DESC) as rn
    FROM PostLinks
),
CombinedQuestionData AS (
    SELECT
        Q.Id AS QuestionId,
        Q.Title,
        Q.Body,
        Q.CreationDate AS QuestionCreationDate,
        Q.LastActivityDate AS QuestionLastActivityDate,
        Q.AcceptedAnswerId,
        PDM.PostScore,
        PDM.ViewCount,
        PDM.AnswerCount,
        PDM.FavoriteCount,
        URS.UserId AS OwnerUserId,
        URS.DisplayName AS OwnerDisplayName,
        URS.Reputation AS OwnerReputation,
        URS.OwnerGoldBadges,
        PDM.EditCount AS QuestionEditCount,
        PDM.LastUserEditDate AS LastQuestionEditDate,
        PDM.DistinctEditors AS DistinctEditorsCount,
        PDM.CloseVoteHistoryCount,
        PDM.FirstCloseVoteDate,
        PDM.UpvoteUsersCount,
        PDM.DownvoteUsersCount,
        QAS.TotalAnswers,
        QAS.AvgAnswerScore,
        QAS.LatestAnswerDate,
        QAS.HasAcceptedAnswerFlag,
        Q.ClosedDate AS QuestionClosedDate,
        Q.CommunityOwnedDate AS QuestionCommunityOwnedDate,
        COALESCE(PCS.TotalComments, 0) AS TotalQuestionComments,
        COALESCE(PCS.AvgCommentScore, 0.0) AS AvgQuestionCommentScore,
        PCS.LatestCommentDate AS LatestQuestionCommentDate,
        (SELECT COUNT(DISTINCT pl.RelatedPostId) FROM PostLinks pl WHERE pl.PostId = Q.Id AND pl.LinkTypeId = 1) AS LinkedPostsCount,
        (SELECT COALESCE(MAX(ph.CreationDate), '1900-01-01') FROM PostHistory ph WHERE ph.PostId = Q.Id AND ph.PostHistoryTypeId = 5 AND ph.UserId IS NOT NULL AND ph.UserId != Q.OwnerUserId) AS LastCommunityBodyEditDate,
        LAG(PDM.PostScore, 1, 0) OVER (PARTITION BY URS.UserId ORDER BY Q.CreationDate) AS PreviousQuestionScoreByOwner,
        RANK() OVER (PARTITION BY DATE_TRUNC('month', Q.CreationDate) ORDER BY PDM.PostScore DESC, PDM.ViewCount DESC) AS RankWithinMonthByScoreViews,
        NTILE(10) OVER (ORDER BY URS.Reputation DESC, URS.TotalPostsByOwner DESC) AS UserReputationTier,
        AcceptedAnswer.Score AS AcceptedAnswerScore,
        AcceptedAnswerURS.DisplayName AS AcceptedAnswerOwnerDisplayName,
        AcceptedAnswer.CreationDate AS AcceptedAnswerCreationDate,
        (SELECT string_agg(ita.TagName, ', ') FROM IndividualTagAnalysis ita WHERE ita.PostId = Q.Id) AS QuestionTagsList,
        LPL.LinkCreationDate AS LatestLinkDate,
        NULLIF(Q.LastEditorUserId, Q.OwnerUserId) AS ActualLastEditorId,
        Users_LastEditor.Reputation AS LastEditorReputation
    FROM Posts Q
    JOIN PostDetailedMetrics PDM ON Q.Id = PDM.PostId
    JOIN UserReputationSnapshot URS ON Q.OwnerUserId = URS.UserId
    LEFT JOIN PostCommentSummary PCS ON Q.Id = PCS.PostId
    LEFT JOIN QuestionAnswerStats QAS ON Q.Id = QAS.QuestionId
    LEFT JOIN Posts AcceptedAnswer ON Q.AcceptedAnswerId = AcceptedAnswer.Id
    LEFT JOIN Users AcceptedAnswerURS ON AcceptedAnswer.OwnerUserId = AcceptedAnswerURS.Id
    LEFT JOIN LatestPostLink LPL ON Q.Id = LPL.PostId AND LPL.rn = 1
    LEFT JOIN Users AS Users_LastEditor ON Q.LastEditorUserId = Users_LastEditor.Id
    WHERE Q.PostTypeId = 1
)
SELECT
    'HighEngagement' AS QueryType,
    CQD.QuestionId,
    CQD.Title,
    CQD.QuestionCreationDate,
    CQD.PostScore,
    CQD.ViewCount,
    CQD.TotalAnswers,
    CQD.TotalQuestionComments,
    CQD.OwnerDisplayName,
    CQD.OwnerReputation,
    CQD.OwnerGoldBadges,
    CQD.QuestionEditCount,
    CQD.LastQuestionEditDate,
    CQD.RankWithinMonthByScoreViews,
    CQD.UserReputationTier,
    CQD.QuestionTagsList,
    CQD.AcceptedAnswerOwnerDisplayName,
    CQD.LastCommunityBodyEditDate,
    CQD.PreviousQuestionScoreByOwner,
    CQD.LatestLinkDate,
    CQD.ActualLastEditorId,
    CQD.LastEditorReputation,
    (CQD.PostScore * 1.0 / NULLIF(CQD.TotalQuestionComments + CQD.TotalAnswers + 1, 0)) AS ScoreEngagementRatio,
    COALESCE(CASE WHEN CQD.QuestionCommunityOwnedDate IS NOT NULL THEN 'Community Owned' ELSE NULL END, 'Not Community Owned') AS CommunityStatus,
    POSITION('bug' IN LOWER(CQD.Title)) > 0 AS IsBugTitle,
    LENGTH(CQD.Body) AS BodyLength
FROM CombinedQuestionData CQD
WHERE CQD.PostScore > 50
  AND (CQD.ViewCount > 5000 OR CQD.TotalAnswers > 5 OR CQD.TotalQuestionComments > 10 OR CQD.QuestionEditCount > 3)
  AND CQD.OwnerReputation > 5000
  AND CQD.QuestionCreationDate BETWEEN '2020-01-01' AND '2023-12-31'
  AND (CQD.QuestionClosedDate IS NULL OR CQD.FirstCloseVoteDate >= '2023-01-01')
  AND CQD.RankWithinMonthByScoreViews <= 10
  AND CQD.UserReputationTier IN (1, 2)

UNION ALL

SELECT
    'UniqueFeatures' AS QueryType,
    CQD.QuestionId,
    CQD.Title,
    CQD.QuestionCreationDate,
    CQD.PostScore,
    CQD.ViewCount,
    CQD.TotalAnswers,
    CQD.TotalQuestionComments,
    CQD.OwnerDisplayName,
    CQD.OwnerReputation,
    CQD.OwnerGoldBadges,
    CQD.QuestionEditCount,
    CQD.LastQuestionEditDate,
    CQD.RankWithinMonthByScoreViews,
    CQD.UserReputationTier,
    CQD.QuestionTagsList,
    CQD.AcceptedAnswerOwnerDisplayName,
    CQD.LastCommunityBodyEditDate,
    CQD.PreviousQuestionScoreByOwner,
    CQD.LatestLinkDate,
    CQD.ActualLastEditorId,
    CQD.LastEditorReputation,
    (CQD.PostScore * 1.0 / NULLIF(CQD.TotalQuestionComments + CQD.TotalAnswers + 1, 0)) AS ScoreEngagementRatio,
    COALESCE(CASE WHEN CQD.QuestionCommunityOwnedDate IS NOT NULL THEN 'Community Owned' ELSE NULL END, 'Not Community Owned') AS CommunityStatus,
    POSITION('bug' IN LOWER(CQD.Title)) > 0 AS IsBugTitle,
    LENGTH(CQD.Body) AS BodyLength
FROM CombinedQuestionData CQD
WHERE CQD.QuestionCommunityOwnedDate IS NOT NULL
  OR (CQD.QuestionTagsList LIKE '%<sql>%' AND CQD.PostScore > 20)
  OR (CQD.AcceptedAnswerId IS NOT NULL AND CQD.AcceptedAnswerScore < 0)
  OR (CQD.LatestLinkDate IS NOT NULL AND CQD.LatestLinkDate >= '2023-01-01')
  OR (CQD.QuestionEditCount > 10 AND CQD.LastEditorReputation IS NULL)
ORDER BY QuestionCreationDate DESC, QuestionId
LIMIT 2000;
