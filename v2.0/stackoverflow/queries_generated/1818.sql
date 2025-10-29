-- {"query": "1818.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3026} 

WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Views AS UserViews,
        U.UpVotes AS UserUpVotes,
        U.DownVotes AS UserDownVotes,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        COUNT(C.Id) AS TotalCommentsMade, -- Comments written by the user
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalVotesCastUp, -- Upvotes cast by the user
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalVotesCastDown, -- Downvotes cast by the user
        COUNT(B.Id) AS TotalBadges,
        MAX(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS HasGoldBadge,
        AVG(P.Score) FILTER (WHERE P.PostTypeId = 1) AS AvgQuestionScore,
        AVG(P.Score) FILTER (WHERE P.PostTypeId = 2) AS AvgAnswerScore,
        COUNT(PH.Id) AS TotalUserHistoryEvents, -- Post history events initiated by this user
        -- Complex calculation: Reputation gain per day active, handling potential division by zero
        COALESCE(CAST(U.Reputation - 1 AS NUMERIC) / NULLIF(EXTRACT(EPOCH FROM (U.LastAccessDate - U.CreationDate)) / 86400, 0), 0) AS RepGainPerActiveDay,
        -- String expression: Check if user's location contains 'USA' or 'Canada' (case-insensitive)
        CASE WHEN U.Location ILIKE '%USA%' OR U.Location ILIKE '%Canada%' THEN TRUE ELSE FALSE END AS IsNorthAmericanUser
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V ON U.Id = V.UserId -- Votes cast by this user
    LEFT JOIN Badges B ON U.Id = B.UserId
    LEFT JOIN PostHistory PH ON U.Id = PH.UserId -- History events initiated by this user
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.UpVotes, U.DownVotes, U.Location
),
PostContentAnalysis AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount AS PostCommentCount, -- Number of comments on this post
        P.FavoriteCount,
        P.ClosedDate,
        P.LastActivityDate,
        P.LastEditDate,
        P.Title,
        P.Body,
        P.Tags,
        -- Correlated subquery: Average comment score for this post
        COALESCE((SELECT AVG(SC.Score) FROM Comments SC WHERE SC.PostId = P.Id), 0) AS AvgCommentScoreForPost,
        -- Total upvotes and downvotes for this specific post
        SUM(CASE WHEN PV.VoteTypeId = 2 THEN 1 ELSE 0 END) AS PostTotalUpVotes,
        SUM(CASE WHEN PV.VoteTypeId = 3 THEN 1 ELSE 0 END) AS PostTotalDownVotes,
        -- String expressions: Check for specific keywords in title or body
        CASE
            WHEN P.Title ILIKE '%sql%' OR P.Body ILIKE '%sql%' OR P.Title ILIKE '%database%' OR P.Body ILIKE '%database%' THEN TRUE
            ELSE FALSE
        END AS ContainsDatabaseKeywords,
        CASE
            WHEN P.Title ILIKE '%performance%' OR P.Body ILIKE '%performance%' OR P.Title ILIKE '%optimization%' OR P.Body ILIKE '%optimization%' THEN TRUE
            ELSE FALSE
        END AS ContainsPerfOptKeywords,
        -- Calculation: The 'activity' duration of the post in hours
        EXTRACT(EPOCH FROM (P.LastActivityDate - P.CreationDate)) / 3600 AS HoursSinceCreationToLastActivity,
        -- String expression/calculation: Percentage of body length being uppercase (rough indicator of 'shouting' or code blocks)
        COALESCE((LENGTH(REPLACE(P.Body, LOWER(P.Body), ''))::NUMERIC / NULLIF(LENGTH(P.Body), 0)) * 100, 0) AS UppercaseBodyPercentage,
        -- String expression: Extract the first tag (if exists)
        TRIM(BOTH '<>' FROM SUBSTRING(P.Tags FROM '(?<=<)[^>]+(?=>)')) AS FirstTag
    FROM Posts P
    LEFT JOIN Votes PV ON P.Id = PV.PostId AND PV.VoteTypeId IN (2, 3) -- Only UpMod/DownMod
    WHERE P.PostTypeId IN (1, 2) -- Focus on Questions (1) and Answers (2)
    GROUP BY P.Id, P.PostTypeId, P.OwnerUserId, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount, P.CommentCount, P.FavoriteCount, P.ClosedDate, P.LastActivityDate, P.LastEditDate, P.Title, P.Body, P.Tags
),
PostHistoryAggregates AS (
    SELECT
        PH.PostId,
        COUNT(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 END) AS CloseEvents,
        COUNT(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 END) AS ReopenEvents,
        COUNT(CASE WHEN PH.PostHistoryTypeId = 12 THEN 1 END) AS DeleteEvents,
        COUNT(CASE WHEN PH.PostHistoryTypeId = 13 THEN 1 END) AS UndeleteEvents,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 END) AS EditEvents, -- Title, Body, Tags edits
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate END) AS LatestCloseDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.CreationDate END) AS LatestReopenDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 12 THEN PH.CreationDate END) AS LatestDeleteDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 13 THEN PH.CreationDate END) AS LatestUndeleteDate,
        -- Correlated Subquery: Get the text of the first body edit if it happened
        (
            SELECT SH.Text
            FROM PostHistory SH
            WHERE SH.PostId = PH.PostId
              AND SH.PostHistoryTypeId = 5 -- Edit Body
            ORDER BY SH.CreationDate ASC
            LIMIT 1
        ) AS FirstBodyEditText,
        -- Window function: Find the next history event type after a close event
        COALESCE(
            (SELECT LEAD(PH2.PostHistoryTypeId) OVER (ORDER BY PH2.CreationDate)
             FROM PostHistory PH2
             WHERE PH2.PostId = PH.PostId AND PH2.PostHistoryTypeId = 10
             ORDER BY PH2.CreationDate LIMIT 1),
            -1
        ) AS PostHistoryTypeAfterFirstClose
    FROM PostHistory PH
    GROUP BY PH.PostId
)
SELECT
    UAS.DisplayName,
    UAS.Reputation,
    UAS.TotalPosts,
    UAS.TotalQuestions,
    UAS.TotalAnswers,
    UAS.AvgQuestionScore,
    UAS.AvgAnswerScore,
    PCA.Title AS QuestionTitle,
    PCA.PostScore AS QuestionScore,
    PCA.ViewCount AS QuestionViewCount,
    PCA.PostCommentCount AS QuestionCommentCount,
    PCA.FavoriteCount AS QuestionFavoriteCount,
    PCA.ContainsPerfOptKeywords,
    PCA.ContainsDatabaseKeywords,
    PHA.CloseEvents,
    PHA.ReopenEvents,
    PHA.EditEvents,
    PHA.LatestCloseDate,
    PHA.LatestReopenDate,
    -- Complicated calculation: Calculate a 'Controversy Index' for the post
    (
        PCA.PostTotalDownVotes +
        (PHA.CloseEvents * 2) + -- Closed posts are more controversial
        (PHA.ReopenEvents * 1.5) + -- Reopened posts add to controversy
        (PCA.PostCommentCount * 0.5) + -- Many comments could indicate discussion/controversy
        ABS(PCA.PostTotalUpVotes - PCA.PostTotalDownVotes) -- Difference between up/down votes
    ) AS PostControversyIndex,
    -- Window function: Rank users by their reputation among those meeting the criteria
    RANK() OVER (ORDER BY UAS.Reputation DESC, UAS.TotalQuestions DESC) AS UserReputationRank,
    -- Window function: Categorize questions by score within their owner's questions into quartiles
    NTILE(4) OVER (PARTITION BY UAS.UserId ORDER BY PCA.PostScore DESC) AS PostScoreQuartileForUser,
    -- Calculation: Date difference in days between post creation and latest reopen date, if reopened (NULL logic)
    COALESCE(EXTRACT(DAY FROM (PHA.LatestReopenDate - PCA.PostCreationDate)), 0) AS DaysToReopen,
    -- String expression and NULL logic: Uppercase first 3 chars of location, default to 'UNKNOWN'
    COALESCE(UPPER(SUBSTRING(U.Location FROM 1 FOR 3)), 'UNKNOWN') AS UserLocationPrefix,
    -- Complicated predicate/expression: Check if the body length changed significantly after the first edit
    CASE
        WHEN PHA.FirstBodyEditText IS NOT NULL AND ABS(LENGTH(PHA.FirstBodyEditText) - LENGTH(PCA.Body)) > 50 THEN TRUE
        ELSE FALSE
    END AS BodyLengthChangedSignificantly,
    -- Correlated Subquery: Get the body of the latest answer provided by the user to their own question
    (
        SELECT SA.Body
        FROM Posts SA
        WHERE SA.ParentId = PCA.PostId
          AND SA.OwnerUserId = UAS.UserId
          AND SA.PostTypeId = 2
        ORDER BY SA.CreationDate DESC
        LIMIT 1
    ) AS LatestSelfAnswerBodySnippet,
    -- Check if the post was closed using an 'Off-topic' reason (CloseReasonId 102 from PostHistory/CloseReasonTypes)
    -- This requires parsing the 'Comment' field in PostHistory if PostHistoryTypeId = 10
    -- (Simplified check, assuming PostHistory.Comment for type 10 directly contains the numeric CloseReasonId)
    EXISTS (
        SELECT 1
        FROM PostHistory PH_CR
        WHERE PH_CR.PostId = PCA.PostId
          AND PH_CR.PostHistoryTypeId = 10
          AND PH_CR.Comment = '102' -- Assuming '102' is the ID for Off-topic
    ) AS WasClosedOffTopic
FROM Users U
JOIN UserActivitySummary UAS ON U.Id = UAS.UserId
LEFT JOIN PostContentAnalysis PCA ON U.Id = PCA.OwnerUserId
LEFT JOIN PostHistoryAggregates PHA ON PCA.PostId = PHA.PostId
WHERE
    PCA.PostTypeId = 1 -- Only consider questions
    AND PCA.ContainsPerfOptKeywords IS TRUE -- Focus on performance/optimization related questions
    AND PHA.CloseEvents > 0 -- Question must have been closed at least once
    AND PHA.ReopenEvents > 0 -- Question must have been reopened at least once
    AND UAS.TotalAnswers > 5 -- User must have answered at least 5 times (high activity)
    AND UAS.Reputation > 5000 -- Filter for established users
    AND PCA.PostScore > 50 -- Only significant questions
    AND (U.Location IS NOT NULL AND TRIM(U.Location) != '') -- Ensure location exists and is not empty
    AND PCA.BodyLength > 150 -- Only questions with substantial body content
    AND UAS.IsNorthAmericanUser = TRUE -- Filter for North American users
    -- Complex predicate with NULL logic and correlated subquery:
    -- Either the user provided an answer to their own question, OR the question has been favorited more than 10 times.
    AND (
        (SELECT 1 FROM Posts A WHERE A.ParentId = PCA.PostId AND A.OwnerUserId = UAS.UserId AND A.PostTypeId = 2 LIMIT 1) IS NOT NULL
        OR PCA.FavoriteCount > 10
    )
    AND PCA.UppercaseBodyPercentage BETWEEN 0.5 AND 10 -- Filter for posts with some, but not excessive, uppercase text
ORDER BY
    UAS.Reputation DESC,
    PostControversyIndex DESC,
    PCA.PostCreationDate DESC
LIMIT 200;
