-- {"query": "1507.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2937} 

WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.Views AS UserProfileViews,
        U.LastAccessDate,
        COUNT(DISTINCT p.Id) AS TotalPostsByOwner,
        COUNT(DISTINCT c.Id) AS TotalCommentsByOwner,
        COUNT(DISTINCT ph.PostId) AS TotalPostsEditedByOwner,
        -- Complicated calculation: Reputation change rate per year (handling division by zero and NULLs)
        CAST(U.Reputation AS numeric) / NULLIF(EXTRACT(EPOCH FROM (NOW() - U.CreationDate)) / (3600 * 24 * 365.25), 0) AS ReputationPerYear,
        -- Conditional aggregation for badge counts
        COUNT(DISTINCT B.Id) FILTER (WHERE B.Class = 1) AS GoldBadgesCount,
        COUNT(DISTINCT B.Id) FILTER (WHERE B.Class = 2) AS SilverBadgesCount,
        COUNT(DISTINCT B.Id) FILTER (WHERE B.Class = 3) AS BronzeBadgesCount
    FROM Users U
    LEFT JOIN Posts p ON U.Id = p.OwnerUserId
    LEFT JOIN Comments c ON U.Id = c.UserId
    LEFT JOIN PostHistory ph ON U.Id = ph.UserId AND ph.PostHistoryTypeId IN (4, 5, 6, 24) -- Edits and suggested edit applied
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.Views, U.LastAccessDate, U.CreationDate
),
PostLifecycle AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.LastActivityDate,
        P.LastEditDate,
        P.ClosedDate,
        -- Counting various history events
        COUNT(PH_Any.Id) AS TotalHistoryEvents,
        COUNT(CASE WHEN PH_Edit.PostHistoryTypeId IN (4, 5, 6, 24) THEN PH_Edit.Id END) AS EditCount,
        COUNT(CASE WHEN PH_Reopen.PostHistoryTypeId = 11 THEN PH_Reopen.Id END) AS ReopenCount,
        MAX(CASE WHEN PH_Close.PostHistoryTypeId = 10 THEN 'Closed' ELSE NULL END) AS IsClosedFlag,
        -- Complicated predicate/NULL logic: Determine closure reason, or 'N/A' if not closed
        COALESCE(MIN(CR.Name), 'N/A') AS PrimaryClosureReasonName,
        MIN(CASE WHEN PH_Close.PostHistoryTypeId = 10 THEN PH_Close.CreationDate END) AS ActualCloseDate,
        -- Calculation for days until closed, or days until current date if not closed
        EXTRACT(EPOCH FROM (COALESCE(P.ClosedDate, NOW()) - P.CreationDate)) / (60 * 60 * 24) AS DaysUntilClosedOrNow
    FROM Posts P
    LEFT JOIN PostHistory PH_Any ON P.Id = PH_Any.PostId
    LEFT JOIN PostHistory PH_Edit ON P.Id = PH_Edit.PostId AND PH_Edit.PostHistoryTypeId IN (4, 5, 6, 24)
    LEFT JOIN PostHistory PH_Reopen ON P.Id = PH_Reopen.PostId AND PH_Reopen.PostHistoryTypeId = 11
    LEFT JOIN PostHistory PH_Close ON P.Id = PH_Close.PostId AND PH_Close.PostHistoryTypeId = 10
    LEFT JOIN CloseReasonTypes CR ON CAST(PH_Close.Comment AS int) = CR.Id -- Assuming Comment stores CloseReasonId
    GROUP BY P.Id, P.PostTypeId, P.CreationDate, P.LastActivityDate, P.LastEditDate, P.ClosedDate
),
AnswerAggregates AS (
    SELECT
        ParentId AS QuestionId,
        AVG(Score) AS AverageAnswerScore,
        MAX(Score) AS MaxAnswerScore,
        COUNT(Id) AS TotalAnswersPublished
    FROM Posts
    WHERE PostTypeId = 2
    GROUP BY ParentId
),
LinkAggregates AS (
    SELECT
        PostId AS QuestionId,
        COUNT(CASE WHEN LinkTypeId = 1 THEN RelatedPostId END) AS LinkedPostsCount,
        COUNT(CASE WHEN LinkTypeId = 3 THEN RelatedPostId END) AS DuplicatePostsCount
    FROM PostLinks
    GROUP BY PostId
),
QuestionBase AS (
    SELECT
        Q.Id AS QuestionId,
        Q.Title AS QuestionTitle,
        Q.Body AS QuestionBody,
        Q.CreationDate AS QuestionCreationDate,
        Q.LastActivityDate,
        Q.Score AS QuestionScore,
        Q.ViewCount AS QuestionViewCount,
        Q.FavoriteCount,
        Q.OwnerUserId,
        Q.AcceptedAnswerId,
        -- String expression to parse tags into an array
        STRING_TO_ARRAY(SUBSTRING(Q.Tags, 2, LENGTH(Q.Tags) - 2), '><') AS TagArray,
        A.CreationDate AS AcceptedAnswerCreationDate,
        A.Score AS AcceptedAnswerScore,
        -- Complicated calculation for time to accept answer (handling NULLs)
        (EXTRACT(EPOCH FROM (A.CreationDate - Q.CreationDate)) / (60 * 60)) AS HoursToAcceptAnswer
    FROM Posts Q
    LEFT JOIN Posts A ON Q.AcceptedAnswerId = A.Id AND A.PostTypeId = 2
    WHERE Q.PostTypeId = 1
),
ExtendedQuestionStats AS (
    SELECT
        QB.QuestionId,
        QB.QuestionTitle,
        QB.OwnerUserId,
        QB.QuestionCreationDate,
        QB.QuestionScore,
        QB.QuestionViewCount,
        QB.FavoriteCount,
        QB.LastActivityDate,
        QB.AcceptedAnswerId,
        QB.TagArray,
        QB.HoursToAcceptAnswer,
        -- COALESCE for NULL logic on aggregates from outer joins
        COALESCE(AA.AverageAnswerScore, 0.0) AS AvgAnswerScore,
        COALESCE(AA.MaxAnswerScore, 0.0) AS MaxAnswerScore,
        COALESCE(AA.TotalAnswersPublished, 0) AS TotalAnswersPublished,
        COALESCE(LA.LinkedPostsCount, 0) AS LinkedPostsCount,
        COALESCE(LA.DuplicatePostsCount, 0) AS DuplicatePostsCount,
        -- Correlated Subquery: Count comments on this question by users with higher reputation than the question owner
        (SELECT COUNT(DISTINCT C.Id)
         FROM Comments C
         JOIN Users CU ON C.UserId = CU.Id
         WHERE C.PostId = QB.QuestionId
           AND C.UserId IS NOT NULL
           AND CU.Reputation > UE.Reputation -- Correlation: depends on UE.Reputation from the outer query
        ) AS CommentsByHigherReputationUsers,
        -- Complicated predicate with string expressions: Check for specific tags and title keywords
        (ARRAY['python', 'javascript'] && QB.TagArray AND QB.QuestionTitle ILIKE '%performance%') AS IsPerformancePythonJsQuestion,
        -- More complex calculation: Score density relative to view count and age (handling division by zero)
        (CAST(QB.QuestionScore AS numeric) / NULLIF(QB.QuestionViewCount, 0)) * (EXTRACT(EPOCH FROM (NOW() - QB.QuestionCreationDate)) / (3600 * 24 * 365.25)) AS ScoreDensityPerViewPerYear,
        -- Window function: Rank questions by score within their creation year
        RANK() OVER (PARTITION BY EXTRACT(YEAR FROM QB.QuestionCreationDate) ORDER BY QB.QuestionScore DESC, QB.QuestionViewCount DESC) AS RankByScoreInCreationYear,
        QB.AcceptedAnswerScore AS AcceptedAnswerScore
    FROM QuestionBase QB
    LEFT JOIN AnswerAggregates AA ON QB.QuestionId = AA.QuestionId
    LEFT JOIN LinkAggregates LA ON QB.QuestionId = LA.QuestionId
    LEFT JOIN UserEngagement UE ON QB.OwnerUserId = UE.UserId -- Needed for correlated subquery
    WHERE QB.QuestionCreationDate >= (NOW() - INTERVAL '6 year') -- Filter for relatively recent questions
      AND QB.QuestionViewCount > 500 -- Filter for questions with significant views
),
EliteQuestionPerformance AS (
    SELECT
        EQS.QuestionId,
        EQS.QuestionTitle,
        UE.DisplayName AS OwnerDisplayName,
        UE.Reputation AS OwnerReputation,
        UE.GoldBadgesCount,
        EQS.QuestionCreationDate,
        EQS.QuestionScore,
        EQS.QuestionViewCount,
        EQS.TotalAnswersPublished,
        EQS.AvgAnswerScore,
        EQS.HoursToAcceptAnswer,
        EQS.LinkedPostsCount,
        EQS.DuplicatePostsCount,
        EQS.CommentsByHigherReputationUsers,
        EQS.IsPerformancePythonJsQuestion,
        EQS.ScoreDensityPerViewPerYear,
        EQS.RankByScoreInCreationYear,
        PL.EditCount,
        PL.IsClosedFlag,
        PL.PrimaryClosureReasonName,
        PL.ReopenCount,
        -- Complex expression with NULL handling and string manipulation for unique identifier
        UPPER(SUBSTRING(COALESCE(EQS.QuestionTitle, 'NO TITLE'), 1, 10)) || '_' || LPAD(CAST(COALESCE(EQS.QuestionId, 0) AS TEXT), 7, '0') AS QuestionIdentifierHash,
        EQS.AcceptedAnswerScore AS AcceptedAnswerScore
    FROM ExtendedQuestionStats EQS
    INNER JOIN UserEngagement UE ON EQS.OwnerUserId = UE.UserId -- INNER JOIN to focus on engaged users
    INNER JOIN PostLifecycle PL ON EQS.QuestionId = PL.PostId
    WHERE UE.Reputation >= 50000 -- Elite users (high reputation)
      AND UE.GoldBadgesCount >= 2 -- At least two gold badges
      AND EQS.AvgAnswerScore > 20 -- Questions with very good average answers
      AND EQS.HoursToAcceptAnswer IS NOT NULL AND EQS.HoursToAcceptAnswer < 48 -- Accepted within 2 days
      AND EQS.QuestionScore > 100 -- Very high score
      AND EQS.IsPerformancePythonJsQuestion = TRUE -- Specific tag and keyword criteria
),
EvolvingOrProblematicQuestions AS (
    SELECT
        EQS.QuestionId,
        EQS.QuestionTitle,
        UE.DisplayName AS OwnerDisplayName,
        UE.Reputation AS OwnerReputation,
        UE.GoldBadgesCount,
        EQS.QuestionCreationDate,
        EQS.QuestionScore,
        EQS.QuestionViewCount,
        EQS.TotalAnswersPublished,
        EQS.AvgAnswerScore,
        EQS.HoursToAcceptAnswer,
        EQS.LinkedPostsCount,
        EQS.DuplicatePostsCount,
        EQS.CommentsByHigherReputationUsers,
        EQS.IsPerformancePythonJsQuestion,
        EQS.ScoreDensityPerViewPerYear,
        EQS.RankByScoreInCreationYear,
        PL.EditCount,
        PL.IsClosedFlag,
        PL.PrimaryClosureReasonName,
        PL.ReopenCount,
        -- Complex expression with NULL handling and string manipulation for unique identifier
        UPPER(SUBSTRING(COALESCE(EQS.QuestionTitle, 'NO TITLE'), 1, 10)) || '_' || LPAD(CAST(COALESCE(EQS.QuestionId, 0) AS TEXT), 7, '0') AS QuestionIdentifierHash,
        EQS.AcceptedAnswerScore AS AcceptedAnswerScore
    FROM ExtendedQuestionStats EQS
    LEFT JOIN UserEngagement UE ON EQS.OwnerUserId = UE.UserId -- LEFT JOIN as owner might not be an elite user
    INNER JOIN PostLifecycle PL ON EQS.QuestionId = PL.PostId
    WHERE PL.EditCount >= 10 -- Many edits indicating evolution
      AND (PL.IsClosedFlag = 'Closed' OR PL.ReopenCount > 0) -- Either closed or reopened
      AND EQS.CommentsByHigherReputationUsers >= 5 -- Significant comments from higher-rep users
      AND EXISTS (SELECT 1 FROM PostHistory PH WHERE PH.PostId = EQS.QuestionId AND PH.PostHistoryTypeId = 16) -- Was community owned at some point
      AND (EQS.DuplicatePostsCount > 0 OR EQS.LinkedPostsCount > 2) -- Linked or duplicated frequently
)
-- Set operator: Combine the two distinct sets of questions for a comprehensive analysis
SELECT * FROM EliteQuestionPerformance
UNION ALL
SELECT * FROM EvolvingOrProblematicQuestions;
