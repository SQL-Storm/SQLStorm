-- {"query": "1850.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2427}
WITH UserEngagementSummary AS (
    SELECT
        U.Id AS UserId,
        COALESCE(U.DisplayName, 'Anonymous') AS UserDisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Views AS UserViews,
        U.UpVotes AS UserReceivedUpVotes,
        U.DownVotes AS UserReceivedDownVotes,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgesCount,
        COUNT(B.Id) AS TotalBadgesCount,
        (SELECT COUNT(DISTINCT V.PostId) FROM Votes V WHERE V.UserId = U.Id AND V.VoteTypeId IN (2, 3)) AS PostsVotedOn,
        (SELECT AVG(P.Score) FROM Posts P WHERE P.OwnerUserId = U.Id AND P.PostTypeId IN (1, 2)) AS AvgPostScore
    FROM Users U
    LEFT JOIN Badges B ON U.Id = B.UserId
    WHERE U.Reputation > 500
      AND U.LastAccessDate >= (DATE '2024-10-01' - INTERVAL '2' YEAR)
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.UpVotes, U.DownVotes
),
QuestionEditAndCloseDetails AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Title,
        P.Tags,
        P.Score,
        P.ViewCount,
        P.AcceptedAnswerId,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.ClosedDate,
        (CASE 
            WHEN P.Tags IS NULL THEN NULL
            ELSE regexp_split_to_array(substr(P.Tags, 2, CASE WHEN char_length(P.Tags) >= 2 THEN char_length(P.Tags) - 2 ELSE 0 END), '><')
         END) AS ParsedTagsArray,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.RevisionGUID END) AS TotalEditRevisions,
        MAX(CASE WHEN PH_Close.PostHistoryTypeId = 10 THEN CRT.Name ELSE NULL END) AS CloseReasonTypeName,
        MAX(CASE WHEN PL.LinkTypeId = 3 THEN 1 ELSE 0 END) AS IsMarkedDuplicate,
        (SELECT COUNT(C.Id) FROM Comments C WHERE C.PostId = P.Id AND C.CreationDate > P.LastEditDate) AS CommentsAfterLastEdit
    FROM Posts P
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId AND PH.PostHistoryTypeId IN (4, 5, 6)
    LEFT JOIN PostHistory PH_Close ON P.Id = PH_Close.PostId AND PH_Close.PostHistoryTypeId = 10
    LEFT JOIN CloseReasonTypes CRT ON CRT.Id = CAST(NULLIF(trim(PH_Close.Comment), '') AS INTEGER)
        AND NULLIF(trim(PH_Close.Comment), '') ~ '^[0-9]+$'
    LEFT JOIN PostLinks PL ON P.Id = PL.PostId AND PL.LinkTypeId = 3
    WHERE P.PostTypeId = 1
      AND P.CreationDate BETWEEN (DATE '2024-10-01' - INTERVAL '5' YEAR) AND DATE '2024-10-01'
    GROUP BY P.Id, P.OwnerUserId, P.CreationDate, P.Title, P.Tags, P.Score, P.ViewCount, P.AcceptedAnswerId, P.AnswerCount, P.CommentCount, P.FavoriteCount, P.ClosedDate, P.LastEditDate
),
AnswerPerformanceMetrics AS (
    SELECT
        A.Id AS AnswerId,
        A.ParentId AS QuestionId,
        A.OwnerUserId AS AnswerOwnerUserId,
        A.CreationDate AS AnswerCreationDate,
        A.Score AS AnswerScore,
        A.CommentCount AS AnswerCommentCount,
        Q.AcceptedAnswerId AS QuestionAcceptedAnswerId,
        Q.Score AS QuestionScore,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS AnswerUpVotes,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS AnswerDownVotes,
        MAX(CASE WHEN A.OwnerUserId = Q.OwnerUserId THEN 1 ELSE 0 END) AS IsSelfAnswer,
        CASE
            WHEN (SELECT COUNT(DISTINCT C.UserId) FROM Comments C WHERE C.PostId = A.Id) > 0 THEN 'HasComments'
            ELSE 'NoComments'
        END AS CommentStatus
    FROM Posts A
    INNER JOIN Posts Q ON A.ParentId = Q.Id
    LEFT JOIN Votes V ON A.Id = V.PostId AND V.VoteTypeId IN (2, 3)
    WHERE A.PostTypeId = 2
    GROUP BY A.Id, A.ParentId, A.OwnerUserId, A.CreationDate, A.Score, A.CommentCount, Q.AcceptedAnswerId, Q.Score, Q.OwnerUserId
)
SELECT
    UES.UserDisplayName,
    UES.Reputation,
    UES.GoldBadgesCount,
    UES.TotalBadgesCount,
    UES.AvgPostScore,
    QED.PostId AS QuestionId,
    QED.Title AS QuestionTitle,
    QED.PostCreationDate,
    QED.Score AS QuestionScore,
    QED.ViewCount AS QuestionViewCount,
    COALESCE(QED.CloseReasonTypeName, 'Not Closed') AS QuestionCloseReason,
    QED.TotalEditRevisions,
    QED.IsMarkedDuplicate,
    QED.CommentsAfterLastEdit,
    T.TagName AS PrimaryTagName,
    T.Count AS TagUseCount,
    APM.AnswerId,
    APM.AnswerOwnerUserId,
    APM.AnswerScore,
    APM.AnswerCommentCount,
    APM.AnswerUpVotes,
    APM.AnswerDownVotes,
    APM.IsSelfAnswer,
    APM.CommentStatus,
    CASE
        WHEN QED.AcceptedAnswerId = APM.AnswerId THEN 'Accepted'
        ELSE 'Not Accepted'
    END AS AcceptanceStatus,
    RANK() OVER (PARTITION BY UES.UserId ORDER BY QED.Score DESC, QED.ViewCount DESC) AS UserQuestionRank,
    NTILE(5) OVER (ORDER BY UES.Reputation DESC, QED.Score DESC, APM.AnswerScore DESC) AS OverallPerformanceQuintile,
    LAG(QED.PostCreationDate, 1, UES.UserCreationDate) OVER (PARTITION BY UES.UserId ORDER BY QED.PostCreationDate) AS PreviousQuestionDate,
    LEAD(QED.PostCreationDate, 1, DATE '2024-10-01') OVER (PARTITION BY UES.UserId ORDER BY QED.PostCreationDate) AS NextQuestionDate,
    (QED.Score * 1.0 / NULLIF(QED.ViewCount, 0)) AS ScorePerViewRatio,
    (APM.AnswerScore * 1.0 / NULLIF(QED.Score, 0)) AS AnswerScoreToQuestionScoreRatio,
    UPPER(SUBSTRING(QED.Title FROM 1 FOR 10)) || '...' || LOWER(RIGHT(QED.Title, 10)) AS AbbreviatedTitle
FROM UserEngagementSummary UES
INNER JOIN QuestionEditAndCloseDetails QED ON UES.UserId = QED.OwnerUserId
LEFT JOIN LATERAL (
    SELECT t.unnest_val AS tag_val
    FROM unnest(QED.ParsedTagsArray) AS t(unnest_val)
) TagName_UN ON TRUE
LEFT JOIN Tags T ON TagName_UN.tag_val = T.TagName
LEFT JOIN AnswerPerformanceMetrics APM ON QED.PostId = APM.QuestionId
WHERE
    (QED.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1 AND CreationDate >= (DATE '2024-10-01' - INTERVAL '1' YEAR))
     OR QED.ViewCount > 500)
    AND (QED.TotalEditRevisions >= 2 OR QED.CommentsAfterLastEdit > 0)
    AND (T.TagName IS NULL OR T.Count > 1000)
    AND (APM.AnswerScore IS NULL OR APM.AnswerScore > 0)
    AND (
        (UES.Reputation / NULLIF(UES.TotalBadgesCount, 0)) > 20
        OR UES.PostsVotedOn > 50
    )
    AND (QED.ClosedDate IS DISTINCT FROM DATE '2024-10-01')

UNION ALL

SELECT
    UES_B.UserDisplayName,
    UES_B.Reputation,
    UES_B.GoldBadgesCount,
    UES_B.TotalBadgesCount,
    UES_B.AvgPostScore,
    NULL AS QuestionId,
    NULL AS QuestionTitle,
    NULL AS PostCreationDate,
    NULL AS QuestionScore,
    NULL AS QuestionViewCount,
    NULL AS QuestionCloseReason,
    NULL AS TotalEditRevisions,
    NULL AS IsMarkedDuplicate,
    NULL AS CommentsAfterLastEdit,
    NULL AS PrimaryTagName,
    NULL AS TagUseCount,
    APM_B.AnswerId,
    APM_B.AnswerOwnerUserId,
    APM_B.AnswerScore,
    APM_B.AnswerCommentCount,
    APM_B.AnswerUpVotes,
    APM_B.AnswerDownVotes,
    APM_B.IsSelfAnswer,
    APM_B.CommentStatus,
    'Not Applicable' AS AcceptanceStatus,
    NULL AS UserQuestionRank,
    NTILE(5) OVER (ORDER BY UES_B.Reputation DESC, APM_B.AnswerScore DESC) AS OverallPerformanceQuintile,
    NULL AS PreviousQuestionDate,
    NULL AS NextQuestionDate,
    NULL AS ScorePerViewRatio,
    (APM_B.AnswerScore * 1.0 / NULLIF(APM_B.QuestionScore, 0)) AS AnswerScoreToQuestionScoreRatio,
    'Answer Only' AS AbbreviatedTitle
FROM UserEngagementSummary UES_B
INNER JOIN AnswerPerformanceMetrics APM_B ON UES_B.UserId = APM_B.AnswerOwnerUserId
WHERE
    APM_B.AnswerScore > 10
    AND APM_B.IsSelfAnswer = 0
    AND APM_B.AnswerCommentCount > 0
    AND APM_B.QuestionAcceptedAnswerId IS DISTINCT FROM APM_B.AnswerId
ORDER BY UserDisplayName, QuestionId, AnswerId NULLS FIRST;