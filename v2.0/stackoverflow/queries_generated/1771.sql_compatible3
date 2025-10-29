WITH UserEngagementSummary AS (
    SELECT
        U.Id AS UserId,
        COALESCE(U.DisplayName, 'Anonymous User') AS UserDisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersProvided,
        COALESCE(SUM(P.Score), 0) AS TotalPostScore,
        COALESCE(SUM(C.Score), 0) AS TotalCommentScore,
        RANK() OVER (ORDER BY U.Reputation DESC, U.CreationDate ASC) AS ReputationRank,
        NTILE(10) OVER (ORDER BY U.Reputation DESC) AS ReputationDecile
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    WHERE U.LastAccessDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
),
PostEditHistory AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.LastEditDate,
        P.LastActivityDate,
        P.Title,
        P.Tags,
        P.Score,
        P.ViewCount,
        P.CommentCount,
        P.FavoriteCount,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS TotalEditCount,
        SUM(CASE WHEN PH.PostHistoryTypeId = 5 THEN 1 ELSE 0 END) AS BodyEditCount,
        SUM(CASE WHEN PH.PostHistoryTypeId = 6 THEN 1 ELSE 0 END) AS TagEditCount,
        (SELECT MAX(PH_inner.CreationDate) FROM PostHistory PH_inner WHERE PH_inner.PostId = P.Id AND PH_inner.PostHistoryTypeId IN (4, 5, 6)) AS LatestEditHistoryDate,
        LAG(P.LastEditDate, 1, P.CreationDate) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS PreviousPostLastEditDate
    FROM Posts P
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    WHERE P.PostTypeId IN (1, 2)
    GROUP BY P.Id, P.OwnerUserId, P.CreationDate, P.LastEditDate, P.LastActivityDate, P.Title, P.Tags, P.Score, P.ViewCount, P.CommentCount, P.FavoriteCount
),
ModerationTrail AS (
    SELECT
        PH.PostId,
        MAX(CASE WHEN PHT.Id = 10 THEN 1 ELSE 0 END) AS WasClosed,
        MAX(CASE WHEN PHT.Id = 11 THEN 1 ELSE 0 END) AS WasReopened,
        MAX(CASE WHEN PHT.Id = 12 THEN 1 ELSE 0 END) AS WasDeleted,
        MIN(CASE WHEN PHT.Id = 10 THEN PH.CreationDate ELSE NULL END) AS FirstClosedDate,
        MAX(CASE WHEN PHT.Id = 11 THEN PH.CreationDate ELSE NULL END) AS LatestReopenedDate,
        COUNT(DISTINCT PH.Id) FILTER (WHERE PHT.Id IN (10, 11, 12, 13, 14, 15, 19, 20)) AS ModerationActionCount,
        LEAD(PH.CreationDate, 1) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS NextHistoryEventDate,
        NULLIF(SUBSTRING(PH.Comment FROM 1 FOR 50), '') AS CloseReasonSnippet
    FROM PostHistory PH
    JOIN PostHistoryTypes PHT ON PH.PostHistoryTypeId = PHT.Id
    WHERE PHT.Id IN (10, 11, 12, 13, 14, 15, 19, 20)
    GROUP BY PH.PostId, PH.CreationDate, PH.Comment
),
TagPerformance AS (
    SELECT
        T.TagName,
        T.Id AS TagId,
        COUNT(DISTINCT P.Id) AS PostsWithTag,
        AVG(P.Score) AS AveragePostScoreForTag,
        AVG(P.ViewCount) AS AverageViewCountForTag,
        (SELECT COUNT(DISTINCT PH.PostId) FROM PostHistory PH WHERE PH.PostHistoryTypeId IN (10, 11) AND PH.PostId IN (
            SELECT P_inner.Id FROM Posts P_inner WHERE P_inner.PostTypeId = 1 AND P_inner.Tags LIKE '%' || T.TagName || '%'
        )) AS ClosedReopenedQuestionsWithTag,
        SUM(T.Count) OVER (ORDER BY T.Count DESC) AS RunningTotalTagCount
    FROM Tags T
    LEFT JOIN Posts P ON P.Tags ILIKE '%' || T.TagName || '%' AND P.PostTypeId = 1
    GROUP BY T.TagName, T.Id, T.Count
    HAVING COUNT(DISTINCT P.Id) > 100
),
LinkedPostsSummary AS (
    SELECT
        PL.PostId,
        COUNT(DISTINCT CASE WHEN PL.LinkTypeId = 1 THEN PL.RelatedPostId ELSE NULL END) AS LinkedToCount,
        COUNT(DISTINCT CASE WHEN PL.LinkTypeId = 3 THEN PL.RelatedPostId ELSE NULL END) AS DuplicateOfCount,
        MAX(CASE WHEN PL.LinkTypeId = 3 THEN 1 ELSE 0 END) AS IsSourceOfDuplicate,
        MIN(PL.CreationDate) AS FirstLinkDate
    FROM PostLinks PL
    GROUP BY PL.PostId
),
QuestionAnswerHierarchy AS (
    SELECT
        Q.Id AS QuestionId,
        Q.Title AS QuestionTitle,
        Q.OwnerUserId AS QuestionOwnerUserId,
        Q.AcceptedAnswerId,
        A.Id AS AnswerId,
        A.OwnerUserId AS AnswerOwnerUserId,
        A.Score AS AnswerScore,
        A.CreationDate AS AnswerCreationDate,
        CASE
            WHEN Q.AcceptedAnswerId IS NOT NULL AND A.CreationDate IS NOT NULL THEN
                EXTRACT(EPOCH FROM (A.CreationDate - Q.CreationDate))
            ELSE NULL
        END AS SecondsToAcceptedAnswer,
        (SELECT COUNT(DISTINCT C_q.Id) FROM Comments C_q WHERE C_q.PostId = Q.Id) AS QuestionCommentCount,
        (SELECT COUNT(DISTINCT C_a.Id) FROM Comments C_a WHERE C_a.PostId = A.Id) AS AnswerCommentCount
    FROM Posts Q
    LEFT JOIN Posts A ON Q.AcceptedAnswerId = A.Id AND A.PostTypeId = 2
    WHERE Q.PostTypeId = 1
),
FirstTag AS (
    SELECT
        Id AS PostId,
        (regexp_split_to_array(substring(Tags from 2 for char_length(Tags) - 2), '><'))[1] AS TagName
    FROM Posts
    WHERE Tags IS NOT NULL AND Tags <> ''
)
SELECT
    UES.UserId,
    UES.UserDisplayName,
    UES.Reputation,
    UES.ReputationRank,
    PH.PostId,
    PH.PostCreationDate,
    PH.Title AS PostTitle,
    PH.Score AS PostScore,
    PH.TotalEditCount,
    PH.BodyEditCount,
    PH.TagEditCount,
    TP.TagName AS PrimaryTag,
    TP.AveragePostScoreForTag,
    MT.WasClosed,
    MT.WasReopened,
    MT.ModerationActionCount,
    LPS.LinkedToCount,
    LPS.DuplicateOfCount,
    QAH.QuestionTitle,
    QAH.AnswerId,
    QAH.AnswerScore,
    QAH.SecondsToAcceptedAnswer,
    EXTRACT(EPOCH FROM (PH.LastActivityDate - PH.PostCreationDate)) / 3600 AS HoursSinceCreationToLastActivity,
    CASE
        WHEN PH.TotalEditCount > 5 AND PH.Score > 50 THEN 'Highly Iterated & Valued'
        WHEN MT.ModerationActionCount > 0 AND PH.Score < 0 THEN 'Contentious & Low Score'
        WHEN LPS.DuplicateOfCount > 0 AND PH.PostCreationDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months') THEN 'Recent Duplicate Target'
        ELSE 'Standard Activity'
    END AS PostLifecycleCategory,
    COALESCE(MT.CloseReasonSnippet, 'N/A') AS LastCloseReasonFragment,
    UPPER(SUBSTRING(UES.UserDisplayName FROM 1 FOR 1)) AS UserInitial,
    SUM(PH.Score) OVER (PARTITION BY UES.UserId ORDER BY PH.PostCreationDate) AS RunningUserPostScore,
    (SELECT AVG(C_sub.Score) FROM Comments C_sub WHERE C_sub.PostId = PH.PostId AND C_sub.UserId = UES.UserId) AS AvgUserCommentScoreOnPost
FROM UserEngagementSummary UES
JOIN PostEditHistory PH ON UES.UserId = PH.OwnerUserId
LEFT JOIN ModerationTrail MT ON PH.PostId = MT.PostId
LEFT JOIN FirstTag FT ON PH.PostId = FT.PostId
LEFT JOIN TagPerformance TP ON FT.TagName = TP.TagName
LEFT JOIN LinkedPostsSummary LPS ON PH.PostId = LPS.PostId
LEFT JOIN QuestionAnswerHierarchy QAH ON PH.PostId = QAH.QuestionId
WHERE
    UES.ReputationRank <= 1000
    AND PH.TotalEditCount >= 2
    AND PH.Score > 0
    AND PH.PostCreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '5 years')
    AND (
        (TP.AveragePostScoreForTag > 20 AND TP.PostsWithTag > 500)
        OR (PH.Tags ILIKE '%<sql>%' OR PH.Tags ILIKE '%<performance>%')
    )
    AND (
        (MT.WasClosed = 1 AND MT.WasReopened = 1)
        OR (LPS.DuplicateOfCount > 0)
        OR (QAH.AcceptedAnswerId IS NOT NULL AND QAH.AnswerScore >= 50)
    )
ORDER BY UES.Reputation DESC, PH.TotalEditCount DESC, PH.Score DESC
LIMIT 500;