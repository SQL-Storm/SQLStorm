WITH UserEngagementStats AS (
    SELECT
        U.Id AS UserId,
        COALESCE(U.DisplayName, 'Anonymous User') AS DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        NTILE(4) OVER (ORDER BY U.Reputation DESC) AS ReputationQuartile,
        U.UpVotes AS TotalUpVotesGiven,
        U.DownVotes AS TotalDownVotesGiven,
        (SELECT COUNT(P.Id) FROM Posts P WHERE P.OwnerUserId = U.Id AND P.PostTypeId = 1) AS QuestionsPosted,
        (SELECT COUNT(P.Id) FROM Posts P WHERE P.OwnerUserId = U.Id AND P.PostTypeId = 2) AS AnswersPosted,
        (SELECT COUNT(C.Id) FROM Comments C WHERE C.UserId = U.Id) AS CommentsMade,
        CASE
            WHEN U.UpVotes > 5000 AND U.Views > 10000 AND U.Reputation > 10000 THEN 'Top Contributor'
            WHEN U.UpVotes > 1000 AND U.Views > 1000 THEN 'Active Participant'
            ELSE 'Occasional User'
        END AS UserActivitySegment,
        SUM(U.UpVotes + U.DownVotes) OVER (ORDER BY U.CreationDate ASC) AS CumulativeVoteInteraction
    FROM Users U
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.UpVotes, U.DownVotes, U.Views
),
QuestionDetailedActivity AS (
    SELECT
        Q.Id AS QuestionId,
        Q.Title AS QuestionTitle,
        Q.OwnerUserId,
        Q.CreationDate AS QuestionCreationDate,
        Q.ViewCount AS QuestionViewCount,
        Q.Score AS QuestionScore,
        Q.AnswerCount AS QuestionTotalAnswerCount,
        Q.FavoriteCount AS QuestionFavoriteCount,
        Q.ClosedDate,
        Q.LastEditDate AS QuestionLastEditDate,
        Q.LastActivityDate AS QuestionLastActivityDate,
        COUNT(DISTINCT PH.Id) AS TotalHistoryEvents,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS MajorEditCount,
        MAX(CASE WHEN PH.PostHistoryTypeId = 16 THEN 1 ELSE 0 END) AS WasCommunityOwnedFlag,
        STRING_AGG(DISTINCT T.TagName, ' | ') FILTER (WHERE T.TagName IS NOT NULL) AS MatchedTagsString,
        RANK() OVER (PARTITION BY Q.OwnerUserId ORDER BY Q.Score DESC, Q.ViewCount DESC) AS UserQuestionScoreRank,
        (SELECT COUNT(DISTINCT PL.RelatedPostId) FROM PostLinks PL WHERE PL.PostId = Q.Id AND PL.LinkTypeId = 3) AS DuplicateLinkCount,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesOnQuestion,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesOnQuestion,
        SUM(CASE WHEN V.VoteTypeId IN (4, 12) THEN 1 ELSE 0 END) AS OffensiveOrSpamVotes
    FROM Posts Q
    JOIN PostTypes PT ON Q.PostTypeId = PT.Id
    LEFT JOIN PostHistory PH ON Q.Id = PH.PostId
    LEFT JOIN (SELECT Id, TagName FROM Tags WHERE TagName IN ('sql', 'performance', 'database', 'optimization', 'query-optimization', 'bigquery', 'postgresql', 'mysql')) T ON Q.Tags LIKE '%' || '<' || T.TagName || '>' || '%'
    LEFT JOIN Votes V ON Q.Id = V.PostId
    WHERE Q.PostTypeId = 1
      AND Q.CreationDate >= DATE '2023-01-01'
      AND Q.ViewCount > 750
      AND Q.AnswerCount > 0
      AND (Q.Tags LIKE '%<sql>%' OR Q.Tags LIKE '%<performance>%' OR Q.Tags LIKE '%<database>%')
      AND Q.Title IS NOT NULL
    GROUP BY Q.Id, Q.Title, Q.OwnerUserId, Q.CreationDate, Q.ViewCount, Q.Score, Q.AnswerCount, Q.FavoriteCount, Q.ClosedDate, Q.LastEditDate, Q.LastActivityDate
),
AnswerQualityMetrics AS (
    SELECT
        A.Id AS AnswerId,
        A.ParentId AS QuestionId,
        A.OwnerUserId AS AnswerOwnerUserId,
        COALESCE(AU.DisplayName, 'Unknown Answerer') AS AnswerOwnerDisplayName,
        A.CreationDate AS AnswerCreationDate,
        A.Score AS AnswerScore,
        A.LastEditDate AS AnswerLastEditDate,
        A.LastEditorUserId AS AnswerLastEditorUserId,
        Q.AcceptedAnswerId,
        CASE
            WHEN Q.AcceptedAnswerId IS NOT NULL AND Q.AcceptedAnswerId = A.Id THEN 'Accepted'
            WHEN Q.AcceptedAnswerId IS NULL AND A.Score > 5 THEN 'Highly Rated (Not Accepted)'
            WHEN A.Score <= 0 THEN 'Poorly Rated'
            ELSE 'Moderately Rated'
        END AS AcceptanceAndScoreStatus,
        CAST(A.Score AS DECIMAL) / NULLIF(Q.ViewCount, 0) AS ScorePerQuestionViewRatio,
        ROW_NUMBER() OVER (PARTITION BY A.ParentId ORDER BY A.Score DESC, A.CreationDate ASC) AS AnswerRankWithinQuestion,
        LAG(A.Score, 1, 0) OVER (PARTITION BY A.ParentId ORDER BY A.CreationDate ASC) AS PreviousAnswerScoreInThread,
        AVG(A.Score) OVER (PARTITION BY A.ParentId) AS AverageAnswerScoreForQuestion,
        COUNT(DISTINCT C.Id) AS CommentsOnAnswerCount,
        MAX(C.CreationDate) AS LatestCommentDateOnAnswer,
        SUM(CASE WHEN C.UserId = A.OwnerUserId THEN 1 ELSE 0 END) AS SelfCommentsOnAnswer
    FROM Posts A
    JOIN Posts Q ON A.ParentId = Q.Id
    LEFT JOIN Users AU ON A.OwnerUserId = AU.Id
    LEFT JOIN Comments C ON A.Id = C.PostId
    WHERE A.PostTypeId = 2
      AND A.CreationDate >= DATE '2023-01-01'
      AND A.Body IS NOT NULL AND LENGTH(A.Body) > 50
    GROUP BY A.Id, A.ParentId, A.OwnerUserId, AU.DisplayName, A.CreationDate, A.Score, A.LastEditDate, A.LastEditorUserId, Q.AcceptedAnswerId, Q.ViewCount
)
SELECT
    UES.UserId,
    UES.DisplayName,
    UES.Reputation,
    UES.ReputationQuartile,
    UES.UserActivitySegment,
    UES.TotalBadges,
    UES.GoldBadges,
    UES.QuestionsPosted,
    UES.AnswersPosted,
    UES.CommentsMade,
    UES.CumulativeVoteInteraction,
    QDA.QuestionId,
    QDA.QuestionTitle,
    QDA.QuestionCreationDate,
    QDA.QuestionScore,
    QDA.QuestionViewCount,
    QDA.QuestionTotalAnswerCount,
    QDA.QuestionFavoriteCount,
    QDA.MatchedTagsString,
    QDA.MajorEditCount AS QuestionMajorEditCount,
    QDA.WasCommunityOwnedFlag,
    QDA.UserQuestionScoreRank,
    QDA.UpVotesOnQuestion,
    QDA.DownVotesOnQuestion,
    QDA.OffensiveOrSpamVotes,
    AQM.AnswerId,
    AQM.AnswerOwnerDisplayName,
    AQM.AnswerScore,
    AQM.AcceptanceAndScoreStatus,
    AQM.ScorePerQuestionViewRatio,
    AQM.AnswerRankWithinQuestion,
    AQM.PreviousAnswerScoreInThread,
    AQM.AverageAnswerScoreForQuestion,
    AQM.CommentsOnAnswerCount,
    AQM.LatestCommentDateOnAnswer,
    AQM.SelfCommentsOnAnswer,
    CASE
        WHEN QDA.ClosedDate IS NOT NULL AND AQM.AnswerScore > 10 THEN 'Closed_ValuedAnswer'
        WHEN QDA.ClosedDate IS NULL AND AQM.AcceptanceAndScoreStatus = 'Accepted' THEN 'Active_AcceptedAnswer'
        WHEN QDA.ClosedDate IS NOT NULL AND AQM.AcceptanceAndScoreStatus = 'Poorly Rated' THEN 'Closed_PoorAnswer'
        ELSE 'Active_OtherAnswer'
    END AS QuestionAnswerLifecycleCategory,
    DENSE_RANK() OVER (ORDER BY UES.Reputation DESC, UES.TotalBadges DESC, (UES.QuestionsPosted + UES.AnswersPosted) DESC) AS OverallUserContributionRank,
    (SELECT COUNT(DISTINCT V.UserId) FROM Votes V WHERE V.PostId = QDA.QuestionId AND V.VoteTypeId = 5 AND V.UserId IS NOT NULL) AS QuestionBookmarkUniqueUsers,
    (SELECT AVG(LENGTH(C.Text)) FROM Comments C WHERE C.PostId = AQM.AnswerId AND C.Text IS NOT NULL) AS AvgCommentTextLengthOnAnswer
FROM UserEngagementStats UES
FULL OUTER JOIN QuestionDetailedActivity QDA ON UES.UserId = QDA.OwnerUserId
FULL OUTER JOIN AnswerQualityMetrics AQM ON QDA.QuestionId = AQM.QuestionId AND UES.UserId = AQM.AnswerOwnerUserId
WHERE (UES.Reputation > 7500 AND UES.QuestionsPosted > 5 AND UES.AnswersPosted > 10)
   OR (UES.ReputationQuartile = 1 AND AQM.AcceptanceAndScoreStatus = 'Accepted' AND AQM.ScorePerQuestionViewRatio > 0.1)
   OR (QDA.QuestionTitle IS NOT NULL AND QDA.QuestionScore > 75 AND QDA.QuestionTotalAnswerCount > 7 AND QDA.MatchedTagsString LIKE '%sql%')
   OR (AQM.AnswerId IS NOT NULL AND AQM.AnswerScore > 20 AND AQM.CommentsOnAnswerCount > 3)
ORDER BY OverallUserContributionRank ASC, UES.Reputation DESC, QDA.QuestionCreationDate DESC NULLS LAST, AQM.AnswerScore DESC NULLS LAST
LIMIT 2000;