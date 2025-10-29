-- {"query": "1969.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3688}
WITH UserEngagementMetrics AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.Views AS UserViews,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        U.UpVotes AS TotalUpVotesGiven,
        U.DownVotes AS TotalDownVotesGiven,
        (U.UpVotes - U.DownVotes) AS NetVotesGiven,
        CASE
            WHEN U.Reputation >= 50000 AND COUNT(DISTINCT B.Id) >= 20 AND U.UpVotes > 1000 THEN 'Legendary'
            WHEN U.Reputation >= 10000 AND COUNT(DISTINCT B.Id) >= 10 THEN 'Elite'
            WHEN U.Reputation >= 2000 AND COUNT(DISTINCT B.Id) >= 3 THEN 'Experienced'
            WHEN U.Reputation >= 200 THEN 'Active'
            ELSE 'Novice'
        END AS UserTier,
        U.CreationDate AS UserCreationDate
    FROM Users U
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.Views, U.UpVotes, U.DownVotes, U.CreationDate
),
PostHistoricalInsights AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.LastEditDate,
        P.LastActivityDate,
        P.ClosedDate,
        COUNT(DISTINCT PH.Id) FILTER (WHERE PH.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9)) AS TotalEditRevertHistoryCount,
        COUNT(DISTINCT PH.Id) FILTER (WHERE PH.PostHistoryTypeId = 10) AS CloseHistoryCount,
        COUNT(DISTINCT PH.Id) FILTER (WHERE PH.PostHistoryTypeId = 11) AS ReopenHistoryCount,
        COUNT(DISTINCT PH.UserId) AS UniqueHistoryContributors,
        RANK() OVER (PARTITION BY P.PostTypeId ORDER BY COUNT(DISTINCT PH.Id) FILTER (WHERE PH.PostHistoryTypeId IN (4, 5, 6)) DESC) AS EditRankWithinPostType,
        AVG(P.Score) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningAvgOwnerPostScore
    FROM Posts P
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    WHERE P.PostTypeId IN (1, 2)
    GROUP BY P.Id, P.PostTypeId, P.OwnerUserId, P.CreationDate, P.LastEditDate, P.LastActivityDate, P.ClosedDate, P.Score
),
TagPerformanceMetrics AS (
    SELECT
        T.TagName,
        COUNT(P.Id) AS TotalPostsInTag,
        AVG(P.Score) AS AvgTagScore,
        AVG(P.ViewCount) AS AvgTagViewCount,
        SUM(CASE WHEN P.PostTypeId = 1 THEN P.AnswerCount ELSE 0 END) AS TotalAnswersInTag,
        MAX(P.CreationDate) AS LatestPostDateInTag,
        MIN(P.CreationDate) AS EarliestPostDateInTag,
        DENSE_RANK() OVER (ORDER BY AVG(P.Score) DESC, COUNT(P.Id) DESC) AS TagScoreRank
    FROM Tags T
    INNER JOIN Posts P ON P.Tags LIKE ( '%' || '<' || T.TagName || '>' || '%' )
    WHERE P.PostTypeId = 1
    GROUP BY T.TagName
    HAVING COUNT(P.Id) >= 50 AND AVG(P.Score) > 0
),
CommentInteractionAnalysis AS (
    SELECT
        C.PostId,
        COUNT(C.Id) AS TotalComments,
        SUM(CASE WHEN LOWER(C.Text) LIKE '%great%' OR LOWER(C.Text) LIKE '%thanks%' OR LOWER(C.Text) LIKE '%helpful%' THEN 1 ELSE 0 END) AS PositiveComments,
        SUM(CASE WHEN LOWER(C.Text) LIKE '%bug%' OR LOWER(C.Text) LIKE '%error%' OR LOWER(C.Text) LIKE '%wrong%' OR LOWER(C.Text) LIKE '%issue%' THEN 1 ELSE 0 END) AS NegativeComments,
        SUM(CASE WHEN LOWER(C.Text) LIKE '%question%' OR LOWER(C.Text) LIKE '%clarify%' THEN 1 ELSE 0 END) AS ClarificationRequests,
        COALESCE(SUM(C.Score), 0) AS TotalCommentScore,
        (
            SELECT C_sub.Text
            FROM Comments C_sub
            WHERE C_sub.PostId = C.PostId
              AND C_sub.UserId = P.OwnerUserId
            ORDER BY C_sub.CreationDate ASC
            LIMIT 1
        ) AS FirstOwnerCommentText,
        NULLIF(SUBSTRING(
            (SELECT C_sub_top.Text FROM Comments C_sub_top WHERE C_sub_top.PostId = C.PostId ORDER BY C_sub_top.Score DESC, C_sub_top.CreationDate DESC LIMIT 1),
            1, 50), '') AS TopCommentExcerpt
    FROM Comments C
    JOIN Posts P ON C.PostId = P.Id
    GROUP BY C.PostId, P.OwnerUserId
)
SELECT
    P.Id AS PostIdentifier,
    'Question_HighViews' AS RecordType,
    PT.Name AS PostTypeName,
    P.Title AS PostTitle,
    P.CreationDate AS PostCreationDate,
    P.Score AS PostScore,
    P.ViewCount AS PostViewCount,
    UEM_P.DisplayName AS OwnerDisplayName,
    UEM_P.UserTier AS OwnerTier,
    UEM_P.Reputation AS OwnerReputation,
    PHI_P.TotalEditRevertHistoryCount AS TotalEditActivity,
    PHI_P.CloseHistoryCount AS PostCloseCount,
    PHI_P.ReopenHistoryCount AS PostReopenCount,
    TPM.TagName AS PrimaryTagName,
    TPM.AvgTagScore,
    CIA.TotalComments AS CommentCount,
    CIA.PositiveComments,
    CIA.NegativeComments,
    CIA.FirstOwnerCommentText,
    CIA.TopCommentExcerpt,
    CAST(EXTRACT(EPOCH FROM (P.LastActivityDate - P.CreationDate)) / (24 * 3600.0) AS NUMERIC(10, 2)) AS DaysActiveSinceCreation,
    COALESCE(P.ClosedDate, TIMESTAMP '1900-01-01 00:00:00') AS EffectiveClosedDate,
    LAG(P.Score, 1, 0) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS PrevPostScoreByOwner,
    RANK() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.ViewCount DESC) AS OwnerPostRankByScoreViews,
    (SELECT COUNT(DISTINCT V.UserId) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 5) AS TotalFavoritesCount,
    L.RelatedPostId AS LinkedPostId,
    LT.Name AS LinkTypeDescription,
    P.AnswerCount,
    (SELECT AVG(C_sub.Score) FROM Comments C_sub WHERE C_sub.PostId = P.Id) AS AvgCommentScore,
    NULLIF(P.Body, '') AS PostBodyContent,
    REGEXP_REPLACE(SUBSTRING(COALESCE(P.Title, 'Untitled Post'), 1, 50), '[^a-zA-Z0-9 ]', '', 'g') AS CleanedTitleExcerpt,
    (SELECT MAX(A_sub.Score) FROM Posts A_sub WHERE A_sub.ParentId = P.Id) AS MaxAnswerScore,
    (SELECT MIN(A_sub.CreationDate) FROM Posts A_sub WHERE A_sub.ParentId = P.Id AND A_sub.AcceptedAnswerId IS NOT NULL) AS FirstAcceptedAnswerDate
FROM Posts P
INNER JOIN PostTypes PT ON P.PostTypeId = PT.Id
LEFT JOIN UserEngagementMetrics UEM_P ON P.OwnerUserId = UEM_P.UserId
LEFT JOIN PostHistoricalInsights PHI_P ON P.Id = PHI_P.PostId
LEFT JOIN CommentInteractionAnalysis CIA ON P.Id = CIA.PostId
LEFT JOIN PostLinks L ON P.Id = L.PostId AND L.LinkTypeId = 1
LEFT JOIN LinkTypes LT ON L.LinkTypeId = LT.Id
LEFT JOIN Tags T ON P.Tags LIKE ( '%' || '<' || T.TagName || '>' || '%' )
LEFT JOIN TagPerformanceMetrics TPM ON T.TagName = TPM.TagName
WHERE P.PostTypeId = 1
  AND P.ViewCount > 5000
  AND P.CreationDate BETWEEN DATE '2021-01-01' AND DATE '2023-12-31'
  AND (P.OwnerUserId IS NOT NULL OR P.CommunityOwnedDate IS NOT NULL)
  AND UEM_P.UserTier IN ('Legendary', 'Elite', 'Experienced')
  AND PHI_P.TotalEditRevertHistoryCount >= 2
  AND TPM.TagScoreRank <= 10
  AND P.Score > (
      SELECT AVG(Score)
      FROM Posts
      WHERE PostTypeId = 1
        AND CreationDate >= P.CreationDate - INTERVAL '365 days'
  )
  AND P.AnswerCount > 0
  AND (P.AcceptedAnswerId IS NOT NULL OR P.ClosedDate IS NOT NULL)
  AND (CIA.NegativeComments IS NULL OR CIA.NegativeComments < 3)

UNION ALL

SELECT
    P.Id AS PostIdentifier,
    'Answer_HighScore' AS RecordType,
    PT.Name AS PostTypeName,
    NULL AS PostTitle,
    P.CreationDate AS PostCreationDate,
    P.Score AS PostScore,
    NULL AS PostViewCount,
    UEM_P.DisplayName AS OwnerDisplayName,
    UEM_P.UserTier AS OwnerTier,
    UEM_P.Reputation AS OwnerReputation,
    PHI_P.TotalEditRevertHistoryCount AS TotalEditActivity,
    PHI_P.CloseHistoryCount AS PostCloseCount,
    PHI_P.ReopenHistoryCount AS PostReopenCount,
    TPM_Parent.TagName AS PrimaryTagName,
    TPM_Parent.AvgTagScore,
    CIA.TotalComments AS CommentCount,
    CIA.PositiveComments,
    CIA.NegativeComments,
    CIA.FirstOwnerCommentText,
    CIA.TopCommentExcerpt,
    CAST(EXTRACT(EPOCH FROM (P.LastActivityDate - P.CreationDate)) / (24 * 3600.0) AS NUMERIC(10, 2)) AS DaysActiveSinceCreation,
    COALESCE(P.ClosedDate, TIMESTAMP '1900-01-01 00:00:00') AS EffectiveClosedDate,
    LAG(P.Score, 1, 0) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS PrevPostScoreByOwner,
    RANK() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.CreationDate DESC) AS OwnerPostRankByScoreViews,
    (SELECT COUNT(DISTINCT V.UserId) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 5) AS TotalFavoritesCount,
    L.RelatedPostId AS LinkedPostId,
    LT.Name AS LinkTypeDescription,
    NULL AS AnswerCount,
    (SELECT AVG(C_sub.Score) FROM Comments C_sub WHERE C_sub.PostId = P.Id) AS AvgCommentScore,
    NULLIF(P.Body, '') AS PostBodyContent,
    REGEXP_REPLACE(SUBSTRING(COALESCE(QP.Title, 'No Question Title'), 1, 50), '[^a-zA-Z0-9 ]', '', 'g') AS CleanedTitleExcerpt,
    (SELECT MAX(A_sub.Score) FROM Posts A_sub WHERE A_sub.ParentId = P.ParentId) AS MaxAnswerScore,
    (SELECT MIN(A_sub.CreationDate) FROM Posts A_sub WHERE A_sub.ParentId = P.ParentId AND A_sub.AcceptedAnswerId IS NOT NULL) AS FirstAcceptedAnswerDate
FROM Posts P
INNER JOIN PostTypes PT ON P.PostTypeId = PT.Id
INNER JOIN Posts QP ON P.ParentId = QP.Id
LEFT JOIN UserEngagementMetrics UEM_P ON P.OwnerUserId = UEM_P.UserId
LEFT JOIN PostHistoricalInsights PHI_P ON P.Id = PHI_P.PostId
LEFT JOIN CommentInteractionAnalysis CIA ON P.Id = CIA.PostId
LEFT JOIN PostLinks L ON P.Id = L.PostId AND L.LinkTypeId = 1
LEFT JOIN LinkTypes LT ON L.LinkTypeId = LT.Id
LEFT JOIN Tags T_Parent ON QP.Tags LIKE ( '%' || '<' || T_Parent.TagName || '>' || '%' )
LEFT JOIN TagPerformanceMetrics TPM_Parent ON T_Parent.TagName = TPM_Parent.TagName
WHERE P.PostTypeId = 2
  AND P.Score >= 50
  AND P.CreationDate BETWEEN DATE '2021-01-01' AND DATE '2023-12-31'
  AND P.OwnerUserId IS NOT NULL
  AND UEM_P.Reputation >= 5000
  AND PHI_P.UniqueHistoryContributors >= 1
  AND TPM_Parent.TagScoreRank <= 5
  AND P.Id = QP.AcceptedAnswerId
  AND (CIA.PositiveComments IS NULL OR CIA.PositiveComments >= 1)
ORDER BY PostCreationDate DESC, PostScore DESC
LIMIT 2000;