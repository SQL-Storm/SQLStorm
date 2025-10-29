-- {"query": "1145.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3172} 

WITH UserEngagement AS (
    -- Summarizes user activity, reputation, and badge statistics.
    -- Uses COALESCE for NULL handling on UserLocation.
    -- Aggregates various counts and sums for posts, comments, and badges.
    SELECT
        U.Id AS UserId,
        U.DisplayName AS UserDisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        COALESCE(U.Location, 'Unknown') AS UserLocation,
        COUNT(DISTINCT P.Id) AS TotalPostsCreated,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        COUNT(DISTINCT B.Id) AS TotalBadgesEarned,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(B.Date) AS LatestBadgeDate,
        AVG(P.Score) FILTER (WHERE P.PostTypeId = 1) AS AvgQuestionScoreAsOwner,
        AVG(P.Score) FILTER (WHERE P.PostTypeId = 2) AS AvgAnswerScoreAsOwner
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.UpVotes, U.DownVotes, U.Location
),
PostAggregates AS (
    -- Calculates aggregated statistics for individual posts (questions or answers).
    -- Includes string manipulation for tags and title/body excerpts.
    -- Features a correlated subquery for TotalBountyPosted.
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        PT.Name AS PostTypeName,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount AS DeclaredAnswerCount,
        P.CommentCount AS PostCommentCount,
        P.FavoriteCount,
        P.ClosedDate,
        P.LastActivityDate,
        P.LastEditDate,
        CASE
            WHEN P.PostTypeId = 1 THEN 'Question'
            WHEN P.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostCategory,
        COALESCE(P.Title, SUBSTRING(P.Body, 1, 100) || '...') AS DisplayTitleOrBodyExcerpt,
        REPLACE(REPLACE(P.Tags, '>', ''), '<', ',') AS TagsCleaned, -- Prepares tags for LIKE predicates
        COUNT(DISTINCT C.Id) AS ActualCommentCount,
        COUNT(DISTINCT V.Id) AS TotalVotesReceived,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        (
            SELECT SUM(V_Bounty.BountyAmount)
            FROM Votes V_Bounty
            WHERE V_Bounty.PostId = P.Id
              AND V_Bounty.VoteTypeId = 8 -- BountyStart VoteType
        ) AS TotalBountyPosted
    FROM Posts P
    JOIN PostTypes PT ON P.PostTypeId = PT.Id
    LEFT JOIN Comments C ON P.Id = C.PostId
    LEFT JOIN Votes V ON P.Id = V.PostId
    GROUP BY P.Id, P.PostTypeId, PT.Name, P.OwnerUserId, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount, P.CommentCount, P.FavoriteCount, P.ClosedDate, P.LastActivityDate, P.LastEditDate, P.Title, P.Body, P.Tags
),
QuestionAnswerChain AS (
    -- Links questions to their answers and applies window functions.
    -- Calculates time differences and answer rankings.
    SELECT
        Q.PostId AS QuestionId,
        Q.OwnerUserId AS QuestionOwnerId,
        Q.PostCreationDate AS QuestionCreationDate,
        Q.PostScore AS QuestionScore,
        Q.ViewCount AS QuestionViewCount,
        Q.FavoriteCount AS QuestionFavoriteCount,
        Q.ClosedDate AS QuestionClosedDate,
        Q.TagsCleaned AS QuestionTags,
        Q.DisplayTitleOrBodyExcerpt AS QuestionTitleExcerpt,
        A.PostId AS AnswerId,
        A.OwnerUserId AS AnswerOwnerId,
        A.PostCreationDate AS AnswerCreationDate,
        A.PostScore AS AnswerScore,
        A.LastEditDate AS AnswerLastEditDate,
        Q_Orig.AcceptedAnswerId AS OriginalAcceptedAnswerId,
        CASE WHEN Q_Orig.AcceptedAnswerId = A.PostId THEN TRUE ELSE FALSE END AS IsAcceptedAnswer,
        ROW_NUMBER() OVER (PARTITION BY Q.PostId ORDER BY A.PostCreationDate) AS AnswerOrderOnQuestion,
        RANK() OVER (PARTITION BY Q.PostId ORDER BY A.PostScore DESC, A.PostCreationDate ASC) AS AnswerScoreRankOnQuestion,
        LAG(A.PostCreationDate, 1, Q.PostCreationDate) OVER (PARTITION BY Q.PostId ORDER BY A.PostCreationDate) AS PreviousAnswerDate,
        (A.PostCreationDate - Q.PostCreationDate) AS TimeToAnswer, -- Date arithmetic
        COALESCE(A.PostScore, 0) + COALESCE(Q.PostScore, 0) AS CombinedPostScore -- NULL logic
    FROM PostAggregates Q
    JOIN Posts Q_Orig ON Q.PostId = Q_Orig.Id AND Q_Orig.PostTypeId = 1 -- Joining with original Posts for AcceptedAnswerId
    LEFT JOIN PostAggregates A ON Q.PostId = A.ParentId AND A.PostTypeId = 2
    WHERE Q.PostTypeId = 1
),
PostEditActivity AS (
    -- Analyzes post history for edit events, moderation, and close reasons.
    -- Uses window functions for ranking history events and LAG for time between events.
    -- Extracts JSON data from PostHistory.Text for complex analysis.
    SELECT
        PH.PostId,
        PH.PostHistoryTypeId,
        PHT.Name AS HistoryTypeName,
        PH.CreationDate AS HistoryEventDate,
        PH.UserId AS HistoryUserId,
        U.DisplayName AS HistoryUserDisplayName,
        PH.Comment AS HistoryComment,
        PH.Text AS HistoryTextContent,
        jsonb_extract_path_text(PH.Text::jsonb, 'OriginalQuestionIds') AS OriginalQuestionIdsJson, -- Extracting from JSON for duplicate info
        CR.Name AS CloseReasonName,
        ROW_NUMBER() OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate DESC) AS LatestHistoryRank,
        LAG(PH.CreationDate, 1) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS PreviousHistoryEventDate,
        COUNT(PH.Id) OVER (PARTITION BY PH.PostId) AS TotalHistoryEventsForPost,
        NTILE(5) OVER (ORDER BY PH.CreationDate) AS HistoryDateQuintile
    FROM PostHistory PH
    JOIN PostHistoryTypes PHT ON PH.PostHistoryTypeId = PHT.Id
    LEFT JOIN Users U ON PH.UserId = U.Id
    LEFT JOIN CloseReasonTypes CR ON PH.PostHistoryTypeId = 10 AND PH.Comment IS NOT NULL AND CR.Id = CAST(PH.Comment AS smallint) -- Joining on CloseReasonTypes via a cast
    WHERE PH.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 10, 11, 12, 13, 14, 15, 19, 20, 35, 36) -- Various significant history types
)
-- Main query combining all CTEs for a comprehensive view.
-- Includes various complex predicates, expressions, and additional window functions.
SELECT
    UE.UserId,
    UE.UserDisplayName,
    UE.Reputation,
    UE.UserCreationDate,
    UE.TotalPostsCreated,
    UE.TotalCommentsMade,
    UE.GoldBadges,
    UE.SilverBadges,
    UE.BronzeBadges,
    QAC.QuestionId,
    QAC.QuestionTitleExcerpt,
    QAC.QuestionCreationDate,
    QAC.QuestionScore,
    QAC.QuestionViewCount,
    QAC.QuestionFavoriteCount,
    QAC.QuestionClosedDate,
    QAC.QuestionTags,
    PA_Q.TotalVotesReceived AS QuestionTotalVotes,
    PA_Q.UpVotesReceived AS QuestionUpVotes,
    PA_Q.DownVotesReceived AS QuestionDownVotes,
    PA_Q.TotalBountyPosted AS QuestionBountyAmount,
    QAC.AnswerId,
    QAC.AnswerOwnerId,
    QAC.AnswerCreationDate,
    QAC.AnswerScore,
    QAC.IsAcceptedAnswer,
    QAC.AnswerOrderOnQuestion,
    QAC.AnswerScoreRankOnQuestion,
    QAC.TimeToAnswer,
    QAC.CombinedPostScore,
    PA_A.ActualCommentCount AS AnswerActualCommentCount,
    PA_A.UpVotesReceived AS AnswerUpVotes,
    PA_A.DownVotesReceived AS AnswerDownVotes,
    MI_Latest.HistoryTypeName AS LatestPostEventType,
    MI_Latest.HistoryEventDate AS LatestPostEventDate,
    MI_Latest.HistoryUserDisplayName AS LatestEventActor,
    MI_Latest.CloseReasonName AS LatestCloseReason,
    MI_Latest.TotalHistoryEventsForPost,
    COALESCE(AGE(QAC.QuestionClosedDate, QAC.QuestionCreationDate), INTERVAL '0 days') AS TimeToClose, -- Calculate time difference with NULL handling
    (
        SELECT COUNT(DISTINCT UserId)
        FROM Badges
        WHERE UserId = UE.UserId AND TagBased = TRUE AND Name ILIKE '%gold%'
    ) AS TagGoldBadgesCount, -- Correlated subquery for tag-based gold badges
    (
        SELECT AVG(PA_Sub.PostScore)
        FROM PostAggregates PA_Sub
        WHERE PA_Sub.PostTypeId = 1
          AND PA_Sub.PostCreationDate < QAC.QuestionCreationDate
          AND PA_Sub.ViewCount > 1000
    ) AS AvgHighViewQuestionScoreBeforeThis, -- Non-correlated subquery for global average
    CASE
        WHEN QAC.QuestionViewCount > 5000 AND QAC.AnswerId IS NULL AND QAC.QuestionClosedDate IS NULL THEN 'ViralUnansweredOpen'
        WHEN QAC.QuestionScore < 0 AND QAC.QuestionClosedDate IS NOT NULL THEN 'NegativeClosed'
        WHEN QAC.IsAcceptedAnswer AND QAC.TimeToAnswer < INTERVAL '1 hour' THEN 'QuickAcceptedSolution'
        WHEN MI_Latest.HistoryTypeName LIKE '%Deleted%' THEN 'DeletedPost'
        ELSE 'Standard'
    END AS QuestionAnalysisCategory,
    EXTRACT(HOUR FROM QAC.QuestionCreationDate) AS CreationHourOfDay,
    EXTRACT(YEAR FROM QAC.QuestionCreationDate) AS CreationYear,
    AVG(QAC.AnswerScore) OVER (PARTITION BY UE.UserLocation ORDER BY QAC.QuestionCreationDate) AS AvgAnswerScoreByLocationRunning, -- Window function with partition
    SUM(QAC.CombinedPostScore) OVER (ORDER BY QAC.QuestionCreationDate ROWS BETWEEN 100 PRECEDING AND CURRENT ROW) AS RollingCombinedScore, -- Window function with frame clause
    'v2.0_ElaborateBenchmark' AS QueryIdentifierString
FROM UserEngagement UE
LEFT JOIN QuestionAnswerChain QAC ON UE.UserId = QAC.QuestionOwnerId
LEFT JOIN PostAggregates PA_Q ON QAC.QuestionId = PA_Q.PostId
LEFT JOIN PostAggregates PA_A ON QAC.AnswerId = PA_A.PostId
LEFT JOIN PostEditActivity MI_Latest ON QAC.QuestionId = MI_Latest.PostId AND MI_Latest.LatestHistoryRank = 1
WHERE UE.Reputation > 1000
  AND QAC.QuestionId IS NOT NULL
  AND QAC.QuestionCreationDate BETWEEN '2019-01-01' AND '2023-12-31'
  AND (QAC.QuestionTags ILIKE '%,sql,%' OR QAC.QuestionTags ILIKE '%,database,%' OR QAC.QuestionTags ILIKE '%,postgres,%')
  AND (QAC.IsAcceptedAnswer IS NULL OR QAC.IsAcceptedAnswer = FALSE OR QAC.AnswerScore > 10) -- Complex NULL logic and conditional filtering
  AND EXISTS (
      SELECT 1 FROM Badges B_Inner
      WHERE B_Inner.UserId = UE.UserId
        AND B_Inner.Class = 1
        AND B_Inner.Name ILIKE '%Pioneer%'
  ) -- Correlated EXISTS subquery for a specific badge
  AND NOT EXISTS (
      SELECT 1 FROM PostLinks PL
      WHERE PL.PostId = QAC.QuestionId AND PL.LinkTypeId = 3 -- Exclude questions that are explicitly duplicates
  )
ORDER BY UE.Reputation DESC, QAC.QuestionCreationDate ASC, QAC.AnswerScore DESC
LIMIT 7500;
