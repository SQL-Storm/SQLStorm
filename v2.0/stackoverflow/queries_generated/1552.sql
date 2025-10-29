-- {"query": "1552.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2875} 

WITH UserProfileSummary AS (
    -- Gathers core user attributes, calculates account age, and counts badge classes using correlated subqueries
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserUpVotes,
        U.DownVotes AS UserDownVotes,
        U.LastAccessDate,
        COALESCE(U.Location, 'Unknown') AS UserLocation, -- NULL logic: provide default for NULL location
        EXTRACT(DAY FROM AGE(CURRENT_TIMESTAMP, U.CreationDate)) AS AccountAgeDays, -- Date calculation (PostgreSQL-specific AGE function)
        (SELECT COUNT(DISTINCT B.Id) FROM Badges B WHERE B.UserId = U.Id AND B.Class = 1) AS GoldBadgesCount, -- Correlated subquery
        (SELECT COUNT(DISTINCT B.Id) FROM Badges B WHERE B.UserId = U.Id AND B.Class = 2) AS SilverBadgesCount -- Correlated subquery
    FROM Users U
    WHERE U.Reputation >= 1000 AND U.DisplayName IS NOT NULL -- Predicate for high-reputation users
    HAVING COUNT(U.Id) > 0 -- Example HAVING clause (always true here, but demonstrates syntax)
),
PostQuestionMetrics AS (
    -- Gathers question-specific data, including scores, view counts, tags, and applies various window functions
    SELECT
        Q.Id AS QuestionId,
        Q.Title AS QuestionTitle,
        Q.CreationDate AS QuestionCreationDate,
        Q.Score AS QuestionScore,
        Q.ViewCount AS QuestionViewCount,
        Q.OwnerUserId AS QuestionOwnerId,
        Q.AcceptedAnswerId,
        Q.AnswerCount,
        Q.CommentCount AS QuestionCommentCount,
        Q.FavoriteCount AS QuestionFavoriteCount,
        REPLACE(REPLACE(Q.Tags, '><', ','), '<', '') AS CleanedTags, -- String manipulation: clean up tags string
        A.Score AS AcceptedAnswerScore,
        A.OwnerUserId AS AcceptedAnswerOwnerId,
        PH_Close.CreationDate AS ClosedEventDate,
        CR.Name AS CloseReasonName,
        COUNT(V.Id) FILTER (WHERE V.VoteTypeId = 2) AS TotalUpVotesOnQuestion, -- Conditional aggregation (PostgreSQL FILTER clause)
        COUNT(V.Id) FILTER (WHERE V.VoteTypeId = 3) AS TotalDownVotesOnQuestion, -- Conditional aggregation
        RANK() OVER (PARTITION BY Q.OwnerUserId ORDER BY Q.Score DESC, Q.CreationDate DESC) AS UserQuestionScoreRank, -- Window function: RANK
        DENSE_RANK() OVER (ORDER BY Q.ViewCount DESC, Q.Score DESC) AS GlobalQuestionViewScoreRank, -- Window function: DENSE_RANK
        LAG(Q.CreationDate, 1, '1970-01-01'::timestamp) OVER (PARTITION BY Q.OwnerUserId ORDER BY Q.CreationDate) AS PreviousQuestionDate, -- Window function: LAG with default
        NTILE(5) OVER (ORDER BY Q.ViewCount DESC) AS ViewCountQuintile, -- Window function: NTILE
        AVG(Q.Score) OVER (PARTITION BY Q.OwnerUserId) AS AvgQuestionScoreByOwner -- Window function: Partitioned AVG
    FROM Posts Q
    LEFT JOIN Posts A ON Q.AcceptedAnswerId = A.Id AND A.PostTypeId = 2
    LEFT JOIN Votes V ON Q.Id = V.PostId AND V.VoteTypeId IN (2, 3)
    LEFT JOIN PostHistory PH_Close ON Q.Id = PH_Close.PostId AND PH_Close.PostHistoryTypeId = 10
    LEFT JOIN CloseReasonTypes CR ON CAST(PH_Close.Comment AS SMALLINT) = CR.Id AND PH_Close.PostHistoryTypeId = 10 -- Type casting
    WHERE Q.PostTypeId = 1 -- Filter for questions only
      AND Q.CreationDate BETWEEN '2018-01-01'::timestamp AND '2023-12-31'::timestamp -- Date range predicate
      AND Q.ViewCount IS NOT NULL -- NULL logic
    GROUP BY
        Q.Id, Q.Title, Q.CreationDate, Q.Score, Q.ViewCount, Q.OwnerUserId, Q.AcceptedAnswerId, Q.AnswerCount, Q.CommentCount, Q.FavoriteCount, Q.Tags,
        A.Score, A.OwnerUserId, PH_Close.CreationDate, CR.Name
),
UnifiedActivityStream AS (
    -- Combines posts and comments into a single activity stream using UNION ALL
    SELECT
        P.OwnerUserId AS ActivityUserId,
        P.Id AS ActivityId,
        P.CreationDate AS ActivityDate,
        P.PostTypeId AS ActivityType,
        P.Score AS ActivityScore,
        'Post' AS ActivitySource,
        LEFT(P.Body, 100) AS ActivityExcerpt, -- String function
        P.LastActivityDate
    FROM Posts P
    WHERE P.PostTypeId IN (1, 2) AND P.OwnerUserId IS NOT NULL
    UNION ALL -- Set operator
    SELECT
        C.UserId AS ActivityUserId,
        C.Id AS ActivityId,
        C.CreationDate AS ActivityDate,
        NULL AS ActivityType,
        C.Score AS ActivityScore,
        'Comment' AS ActivitySource,
        LEFT(C.Text, 100) AS ActivityExcerpt, -- String function
        NULL AS LastActivityDate
    FROM Comments C
    WHERE C.UserId IS NOT NULL
),
PostEditAndLinkAnalysis AS (
    -- Analyzes post history for edits and related post links, including a correlated subquery for unique editors
    SELECT
        P.Id AS PostId,
        MAX(CASE WHEN PH.PostHistoryTypeId IN (4,5,6) THEN PH.CreationDate ELSE NULL END) AS LastEditDate,
        MAX(CASE WHEN PH.PostHistoryTypeId IN (12,13) THEN PH.CreationDate ELSE NULL END) AS LastDeleteUndeleteDate,
        COUNT(DISTINCT PH.Id) FILTER (WHERE PH.PostHistoryTypeId IN (4,5,6)) AS TotalEditEvents, -- Conditional aggregation
        SUM(CASE WHEN PL.LinkTypeId = 1 THEN 1 ELSE 0 END) AS LinkedPostsCount,
        SUM(CASE WHEN PL.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicatePostsCount,
        (SELECT COUNT(DISTINCT PH2.UserId) FROM PostHistory PH2 WHERE PH2.PostId = P.Id AND PH2.PostHistoryTypeId IN (4,5,6)) AS UniqueEditorsCount, -- Correlated subquery
        AVG(LENGTH(PH.Text)) FILTER (WHERE PH.PostHistoryTypeId = 5 AND PH.Text IS NOT NULL) AS AvgBodyEditLengthChange -- String length and conditional aggregation
    FROM Posts P
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    LEFT JOIN PostLinks PL ON P.Id = PL.PostId
    WHERE P.PostTypeId = 1 -- Focus on questions for this analysis
    GROUP BY P.Id
)
-- Final result: Detailed analysis of highly reputed users and their top questions, integrating data from all CTEs
SELECT
    UPS.UserId,
    UPS.DisplayName,
    UPS.Reputation,
    UPS.AccountAgeDays,
    UPS.UserProfileViews,
    UPS.GoldBadgesCount,
    PQM.QuestionId,
    PQM.QuestionTitle,
    PQM.QuestionCreationDate,
    PQM.QuestionScore,
    PQM.QuestionViewCount,
    PQM.AnswerCount,
    PQM.QuestionCommentCount,
    PQM.QuestionFavoriteCount,
    PQM.CleanedTags,
    PQM.AcceptedAnswerScore,
    PQM.ClosedEventDate,
    PQM.CloseReasonName,
    PQM.TotalUpVotesOnQuestion,
    PQM.TotalDownVotesOnQuestion,
    PQM.UserQuestionScoreRank,
    PQM.GlobalQuestionViewScoreRank,
    EXTRACT(HOUR FROM (PQM.QuestionCreationDate - PQM.PreviousQuestionDate)) AS HoursSincePrevQuestion, -- Date arithmetic
    PQM.ViewCountQuintile,
    PQM.AvgQuestionScoreByOwner,
    PEALA.LastEditDate AS QuestionLastEditDate,
    PEALA.TotalEditEvents,
    PEALA.LinkedPostsCount,
    PEALA.DuplicatePostsCount,
    PEALA.UniqueEditorsCount,
    (SELECT AVG(CAST(V.BountyAmount AS NUMERIC)) FROM Votes V WHERE V.PostId = PQM.QuestionId AND V.VoteTypeId = 8 AND V.BountyAmount IS NOT NULL) AS AvgBountyAmount, -- Correlated subquery with numeric calculation
    COALESCE(PLE.EventDate, '1900-01-01'::timestamp) AS LastRelevantPostHistoryEventDate, -- NULL logic, default date for missing
    NULLIF(PLE.EventDetails, '') AS LastEventDetails, -- NULL logic: return NULL if string is empty
    UAS_Agg.ActivityDate AS LatestUserActivityDate,
    UAS_Agg.ActivitySource AS LatestUserActivitySource,
    UAS_Agg.ActivityScore AS LatestUserActivityScore,
    CASE
        WHEN PQM.QuestionScore > 1000 AND PQM.AnswerCount > 10 THEN 'Elite Question'
        WHEN PQM.QuestionScore > 200 AND PQM.AnswerCount > 3 THEN 'High Impact Question'
        WHEN PQM.QuestionScore > 50 THEN 'Engaging Question'
        ELSE 'Standard Question'
    END AS QuestionImpactCategory, -- Complex conditional expression
    LENGTH(PQM.QuestionTitle) AS TitleLength, -- String function
    MAX(CASE WHEN PQM.CleanedTags ILIKE '%sql%' THEN 1 ELSE 0 END) AS HasSqlTag, -- Conditional aggregation with string pattern matching
    MAX(CASE WHEN PQM.CleanedTags ILIKE '%python%' THEN 1 ELSE 0 END) AS HasPythonTag,
    ROW_NUMBER() OVER (PARTITION BY UPS.UserId ORDER BY PQM.QuestionScore DESC) AS UserTopQuestionSeq -- Window function: ROW_NUMBER
FROM UserProfileSummary UPS
INNER JOIN PostQuestionMetrics PQM ON UPS.UserId = PQM.QuestionOwnerId
LEFT JOIN PostEditAndLinkAnalysis PEALA ON PQM.QuestionId = PEALA.PostId
LEFT JOIN (
    -- Subquery to get the most recent lifecycle event for each post
    SELECT
        PH.PostId,
        PH.CreationDate AS EventDate,
        PH.Text AS EventDetails,
        PH.PostHistoryTypeId,
        ROW_NUMBER() OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate DESC) as rn -- Window function
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (1,2,3,4,5,6,10,11,12,13,14,15) -- Specific history types
) PLE ON PQM.QuestionId = PLE.PostId AND PLE.rn = 1
LEFT JOIN (
    -- Aggregates UnifiedActivityStream to get the latest activity for each user
    SELECT
        ActivityUserId,
        MAX(ActivityDate) AS ActivityDate,
        -- Use KEEP (DENSE_RANK LAST ORDER BY) for specific DBMS (like Oracle/PostgreSQL) or use another CTE for generic SQL
        MAX(ActivitySource) FILTER (WHERE ActivityDate = MAX(ActivityDate) OVER (PARTITION BY ActivityUserId)) AS ActivitySource, -- PostgreSQL-specific example for LAST value
        MAX(ActivityScore) FILTER (WHERE ActivityDate = MAX(ActivityDate) OVER (PARTITION BY ActivityUserId)) AS ActivityScore
    FROM UnifiedActivityStream
    GROUP BY ActivityUserId
) UAS_Agg ON UPS.UserId = UAS_Agg.ActivityUserId
WHERE UPS.Reputation > 5000 -- Final filtering on user reputation
  AND PQM.QuestionScore > 50 -- Final filtering on question score
  AND PQM.ViewCountQuintile IN (1, 2) -- Final filtering: top 40% most viewed questions
  AND PQM.CleanedTags IS NOT NULL AND PQM.CleanedTags <> '' -- NULL logic and string predicate
ORDER BY
    UPS.Reputation DESC,
    PQM.GlobalQuestionViewScoreRank ASC,
    QuestionLastEditDate DESC NULLS LAST, -- ORDER BY with NULLS LAST
    PQM.QuestionCreationDate DESC
LIMIT 2000;
