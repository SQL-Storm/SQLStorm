-- {"query": "19083.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3211} 

WITH UserEngagement AS (
    -- CTE 1: Aggregates user-level engagement metrics, filtering out very inactive users early.
    -- Calculates total posts, questions, answers, comments, accepted answers, and days since creation.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.Views AS UserProfileViews,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        SUM(P.Score) AS TotalPostScore,
        SUM(COALESCE(P.AnswerCount, 0)) AS TotalAnswersReceived,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        SUM(CASE WHEN P.AcceptedAnswerId IS NOT NULL AND P.PostTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedAnswersForQuestions,
        SUM(CASE WHEN EXISTS (SELECT 1 FROM Posts A WHERE A.Id = P.AcceptedAnswerId AND A.OwnerUserId = U.Id) THEN 1 ELSE 0 END) AS AcceptedAnswersByThisUser,
        -- Calculate days active, ensuring it's not negative.
        GREATEST(0, EXTRACT(EPOCH FROM (U.LastAccessDate - U.CreationDate)) / 86400.0) AS DaysSinceCreation,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        MAX(P.CreationDate) AS LastPostDate,
        MAX(C.CreationDate) AS LastCommentDate
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.Views, U.LastAccessDate
    HAVING COUNT(DISTINCT P.Id) + COUNT(DISTINCT C.Id) > 10 -- Filter for users with at least some combined activity
),
PostEditHistory AS (
    -- CTE 2: Analyzes post edit history, including close/reopen events, and calculates average body length changes.
    SELECT
        PH.PostId,
        MIN(PH.CreationDate) AS InitialCreationDate,
        MAX(PH.CreationDate) AS LastEditOrActivityDate,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 END) AS EditCount, -- Title, Body, Tags edits
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (10, 12) THEN 1 END) AS CloseDeleteCount, -- Post Closed or Post Deleted
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (11, 13) THEN 1 END) AS ReopenUndeleteCount, -- Post Reopened or Post Undeleted
        -- Aggregates close reasons and other comments from PostHistory, using CloseReasonTypes for context.
        STRING_AGG(DISTINCT CASE
                                WHEN PH.Comment IS NOT NULL AND PH.PostHistoryTypeId = 10 AND PH.Comment ~ '^[0-9]+$'
                                    THEN COALESCE(CRT.Name, 'Reason ID: ' || PH.Comment) -- Try to map numeric comment to close reason
                                WHEN PH.Comment IS NOT NULL THEN PH.Comment
                                ELSE NULL
                            END, '; ') FILTER (WHERE PH.PostHistoryTypeId = 10 OR PH.Comment IS NOT NULL) AS CloseAndHistoryComments,
        MAX(CASE WHEN PH.PostHistoryTypeId = 16 THEN 'Yes' ELSE 'No' END) AS WasCommunityOwned,
        -- Calculates the average absolute length change in body edits, treating the initial text as the 'previous' for the first edit.
        COALESCE(AVG(ABS(LENGTH(PH.Text) - LAG(LENGTH(PH.Text), 1, LENGTH(PH.Text)) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate))), 0) AS AvgBodyLengthChange
    FROM PostHistory PH
    LEFT JOIN CloseReasonTypes CRT ON PH.PostHistoryTypeId = 10 AND PH.Comment ~ '^[0-9]+$' AND CRT.Id = PH.Comment::smallint
    GROUP BY PH.PostId
),
SignificantQuestions AS (
    -- CTE 3: Identifies questions meeting high engagement criteria (score and view count).
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.Title,
        P.Body,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.ClosedDate,
        COALESCE(P.AcceptedAnswerId, -1) AS AcceptedAnswerId, -- Use -1 if no accepted answer
        ARRAY_TO_STRING(ARRAY(SELECT UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><')) LIMIT 1), '') AS PrimaryTag,
        LENGTH(P.Body) AS BodyLength,
        'Question' AS PostCategory
    FROM Posts P
    WHERE P.PostTypeId = 1
      AND P.Score >= 10
      AND P.ViewCount >= 1000
),
SignificantAnswers AS (
    -- CTE 4: Identifies answers meeting high engagement criteria (score).
    -- Retrieves tags from their parent question.
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.Title, -- Answer title usually refers to the question's title
        P.Body,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score,
        COALESCE(P.ViewCount, 0) AS ViewCount, -- ViewCount is usually NULL for answers
        COALESCE(P.AnswerCount, 0) AS AnswerCount, -- AnswerCount is usually NULL for answers
        P.CommentCount,
        P.FavoriteCount,
        P.ClosedDate,
        -1 AS AcceptedAnswerId, -- AcceptedAnswerId is not applicable for answers themselves
        ARRAY_TO_STRING(ARRAY(SELECT UNNEST(string_to_array(SUBSTRING(QP.Tags FROM 2 FOR LENGTH(QP.Tags) - 2), '><')) LIMIT 1), '') AS PrimaryTag, -- Get tag from parent question
        LENGTH(P.Body) AS BodyLength,
        'Answer' AS PostCategory
    FROM Posts P
    JOIN Posts QP ON P.ParentId = QP.Id AND QP.PostTypeId = 1 -- Join to parent question for context/tags
    WHERE P.PostTypeId = 2
      AND P.Score >= 25 -- Higher score threshold for significant answers
),
CombinedSignificantPosts AS (
    -- CTE 5: Combines significant questions and answers using UNION ALL.
    -- Adds correlated subquery for latest comment and window function for score relativity.
    SELECT
        T.*,
        -- Correlated subquery: Retrieves the latest comment text for the post
        (SELECT C.Text FROM Comments C WHERE C.PostId = T.PostId ORDER BY C.CreationDate DESC LIMIT 1) AS LatestCommentText,
        -- Window function: Calculates the post's score relative to the average score for its specific PostTypeId
        T.Score - AVG(T.Score) OVER (PARTITION BY T.PostTypeId) AS ScoreRelativeToTypeAvg
    FROM (
        SELECT * FROM SignificantQuestions
        UNION ALL
        SELECT * FROM SignificantAnswers
    ) AS T
),
RelatedPostMetrics AS (
    -- CTE 6: Analyzes linked and duplicate posts, attempting to link PostHistory for duplicate closures.
    SELECT
        PL.PostId,
        COUNT(DISTINCT PL.RelatedPostId) AS LinkedPostCount,
        COUNT(DISTINCT CASE WHEN PL.LinkTypeId = 3 THEN PL.RelatedPostId END) AS DuplicatePostCount,
        -- Attempts to find the creation date of a PostHistory entry indicative of a duplicate closure
        MAX(PH.CreationDate) FILTER (WHERE PH.Text LIKE '%OriginalQuestionIds%') AS LastDuplicateDecisionDate
    FROM PostLinks PL
    LEFT JOIN PostHistory PH ON PL.PostId = PH.PostId
                             AND PH.PostHistoryTypeId = 10 -- Post Closed event
    GROUP BY PL.PostId
)
-- Main Query: Combines all CTEs to generate a comprehensive analytical report on user contributions and post lifecycle.
SELECT
    UE.UserId,
    UE.DisplayName,
    UE.Reputation,
    UE.TotalPosts,
    UE.TotalBadges,
    UE.UserProfileViews,
    UE.DaysSinceCreation,
    CSP.PostId,
    CSP.PostCategory,
    CSP.Title,
    CSP.PostCreationDate,
    CSP.Score,
    CSP.ViewCount,
    CSP.AnswerCount,
    CSP.CommentCount,
    CSP.FavoriteCount,
    CSP.PrimaryTag,
    CSP.BodyLength,
    PEH.EditCount,
    PEH.InitialCreationDate,
    PEH.LastEditOrActivityDate,
    PEH.CloseDeleteCount,
    PEH.ReopenUndeleteCount,
    PEH.CloseAndHistoryComments,
    PEH.WasCommunityOwned,
    PEH.AvgBodyLengthChange,
    COALESCE(RPM.LinkedPostCount, 0) AS LinkedPostCount,
    COALESCE(RPM.DuplicatePostCount, 0) AS DuplicatePostCount,
    -- COALESCE for NULL dates in duplicate decision, providing a default past date
    COALESCE(RPM.LastDuplicateDecisionDate, '1900-01-01 00:00:00') AS EffectiveLastDuplicateDecisionDate,
    CSP.LatestCommentText,
    CSP.ScoreRelativeToTypeAvg,
    -- Window function: Ranks posts by score (and view count) within each user's contributions
    RANK() OVER (PARTITION BY UE.UserId ORDER BY CSP.Score DESC, CSP.ViewCount DESC, CSP.PostCreationDate DESC) AS UserPostRank,
    -- Window function: Calculates the cumulative sum of scores for a user's posts, ordered by creation date
    SUM(CSP.Score) OVER (PARTITION BY UE.UserId ORDER BY CSP.PostCreationDate) AS CumulativePostScore,
    -- Complicated predicate/expression: Categorizes post longevity and activity based on various historical events
    CASE
        WHEN CSP.ClosedDate IS NOT NULL AND PEH.ReopenUndeleteCount = 0 THEN 'Permanently Closed'
        WHEN PEH.ReopenUndeleteCount > 0 AND PEH.CloseDeleteCount > 0 THEN 'Closed and Reopened'
        WHEN CSP.PostCreationDate < (NOW() - INTERVAL '1 year') AND PEH.LastEditOrActivityDate IS NULL THEN 'Dormant Old Post'
        WHEN CSP.PostCreationDate >= (NOW() - INTERVAL '3 months') AND COALESCE(PEH.EditCount, 0) = 0 THEN 'New Unedited Post'
        ELSE 'Active/Evolving Post'
    END AS PostLifecycleStatus,
    -- String expression: Generates a concise content summary from title, latest comment, and primary tag
    TRIM(SUBSTRING(COALESCE(CSP.Title, '[No Title]') || ' - ' || COALESCE(CSP.LatestCommentText, '[No Recent Comment]') || ' (' || COALESCE(CSP.PrimaryTag, 'untagged') || ')', 1, 150)) AS ContentSummary,
    -- Correlated subquery in SELECT: Checks if the user has any tag-based badge matching the post's primary tag
    (
        SELECT COUNT(B.Id) > 0
        FROM Badges B
        WHERE B.UserId = UE.UserId
          AND B.TagBased = TRUE
          AND LOWER(B.Name) = LOWER(CSP.PrimaryTag)
    ) AS HasTagBadge,
    -- Complex calculation with NULL logic: Computes a weighted "CalculatedImpactScore" for each post
    (CSP.Score * 0.7 + COALESCE(CSP.FavoriteCount, 0) * 0.5 + COALESCE(CSP.CommentCount, 0) * 0.3 + COALESCE(CSP.ViewCount, 0) * 0.01) *
    (CASE WHEN PEH.WasCommunityOwned = 'Yes' THEN 0.8 ELSE 1.0 END) / -- Community owned might reduce individual impact
    (CASE WHEN COALESCE(PEH.CloseDeleteCount, 0) > 0 THEN 2.0 ELSE 1.0 END) -- Closed/deleted posts have reduced impact
    AS CalculatedImpactScore
FROM UserEngagement UE
JOIN CombinedSignificantPosts CSP ON UE.UserId = CSP.OwnerUserId
LEFT JOIN PostEditHistory PEH ON CSP.PostId = PEH.PostId
LEFT JOIN RelatedPostMetrics RPM ON CSP.PostId = RPM.PostId
WHERE UE.Reputation > 5000 -- Focus on highly reputed users
  AND CSP.ScoreRelativeToTypeAvg > 0 -- Only posts performing better than average for their type
  AND UE.DaysSinceCreation >= 180 -- User active for at least 6 months
  AND CSP.PostCategory = 'Question' -- For this final analysis, let's focus on initial questions
  AND (CSP.Title IS NOT NULL AND CSP.Title != '') -- Ensure the post has a valid title
  AND (CSP.PrimaryTag IS NOT NULL AND CSP.PrimaryTag != '') -- Ensure the post has a primary tag
  AND CSP.PostCreationDate BETWEEN '2015-01-01' AND '2023-01-01' -- Limit date range for active posts
ORDER BY CalculatedImpactScore DESC, UE.Reputation DESC, UserPostRank ASC
LIMIT 1000;
