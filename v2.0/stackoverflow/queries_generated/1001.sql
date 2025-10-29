-- {"query": "1001.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3310} 

WITH CombinedActivityEvents AS (
    -- Gathers all user-owned posts and comments to calculate overall engagement
    SELECT
        'Post' AS EventType,
        Id AS EntityId,
        OwnerUserId AS UserId,
        CreationDate,
        Score,
        PostTypeId -- To distinguish questions/answers later
    FROM Posts
    WHERE OwnerUserId IS NOT NULL AND PostTypeId IN (1, 2) -- Only questions and answers for owned posts
    UNION ALL
    SELECT
        'Comment' AS EventType,
        Id AS EntityId,
        UserId,
        CreationDate,
        Score,
        NULL AS PostTypeId -- Comments don't have PostTypeId
    FROM Comments
    WHERE UserId IS NOT NULL
),
UserEngagement AS (
    -- Summarizes user-specific activity, reputation, and moderation impact
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.UpVotes,
        U.DownVotes,
        COUNT(DISTINCT CASE WHEN CAE.EventType = 'Post' THEN CAE.EntityId END) AS TotalPosts,
        SUM(CASE WHEN CAE.EventType = 'Post' AND CAE.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN CAE.EventType = 'Post' AND CAE.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COUNT(DISTINCT CASE WHEN CAE.EventType = 'Comment' THEN CAE.EntityId END) AS TotalComments,
        SUM(CASE WHEN CAE.EventType = 'Post' THEN CAE.Score ELSE 0 END) AS TotalPostScoreReceived,
        SUM(V.BountyAmount) AS TotalBountyGiven,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        AVG(CASE WHEN CAE.EventType = 'Post' THEN CAE.Score ELSE NULL END) AS AvgPostScore,
        EXTRACT(EPOCH FROM (NOW() - U.CreationDate)) / (60 * 60 * 24 * 365.25) AS YearsActive
        -- Correlated subqueries for moderation actions on user's posts
        , (
            SELECT COUNT(DISTINCT P_Closed.Id)
            FROM Posts P_Closed
            LEFT JOIN PostHistory PH_C ON P_Closed.Id = PH_C.PostId
            WHERE P_Closed.OwnerUserId = U.Id
              AND PH_C.PostHistoryTypeId = 10 -- Post Closed
              AND PH_C.UserId IS DISTINCT FROM U.Id -- Closed by someone else or community
        ) AS PostsClosedByOthers
        , (
            SELECT COUNT(DISTINCT P_Reopened.Id)
            FROM Posts P_Reopened
            LEFT JOIN PostHistory PH_R ON P_Reopened.Id = PH_R.PostId
            WHERE P_Reopened.OwnerUserId = U.Id
              AND PH_R.PostHistoryTypeId = 11 -- Post Reopened
              AND PH_R.UserId IS DISTINCT FROM U.Id -- Reopened by someone else or community
        ) AS PostsReopenedByOthers
    FROM Users U
    LEFT JOIN CombinedActivityEvents CAE ON U.Id = CAE.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    LEFT JOIN Votes V ON U.Id = V.UserId AND V.VoteTypeId = 8 -- BountyStart
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.UpVotes, U.DownVotes
),
PostQualityMetrics AS (
    -- Calculates various quality and engagement metrics for questions
    SELECT
        Q.Id AS QuestionId,
        Q.Title AS QuestionTitle,
        Q.CreationDate AS QuestionCreationDate,
        Q.Score AS QuestionScore,
        Q.ViewCount,
        Q.OwnerUserId,
        Q.AnswerCount AS DeclaredAnswerCount,
        Q.Tags, -- Include tags for later processing
        COUNT(A.Id) AS ActualAnswerCount,
        AVG(A.Score) AS AvgAnswerScore,
        MAX(A.Score) AS MaxAnswerScore,
        SUM(CASE WHEN A.Id = Q.AcceptedAnswerId THEN 1 ELSE 0 END) AS HasAcceptedAnswer,
        SUM(CASE WHEN PL.LinkTypeId = 1 THEN 1 ELSE 0 END) AS LinkedPostsCount,
        SUM(CASE WHEN PL.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicatePostsCount,
        EXTRACT(EPOCH FROM (Q.LastActivityDate - Q.CreationDate)) / (60 * 60 * 24) AS DaysActive, -- Post's active duration in days
        COALESCE(MAX(PH_Edit.CreationDate), Q.CreationDate) AS LastContentEditDate,
        -- Correlated subquery: counts answers with positive score and existing owner
        (SELECT COUNT(DISTINCT P_Inner.Id) FROM Posts P_Inner WHERE P_Inner.ParentId = Q.Id AND P_Inner.Score > 0 AND P_Inner.OwnerUserId IS NOT NULL) AS EffectiveAnswerCount
    FROM Posts Q
    LEFT JOIN Posts A ON Q.Id = A.ParentId AND A.PostTypeId = 2 -- Answers to the question
    LEFT JOIN PostLinks PL ON Q.Id = PL.PostId OR Q.Id = PL.RelatedPostId
    LEFT JOIN PostHistory PH_Edit ON Q.Id = PH_Edit.PostId AND PH_Edit.PostHistoryTypeId IN (5, 6) -- Edit Body, Edit Tags
    WHERE Q.PostTypeId = 1 -- Only questions
    GROUP BY Q.Id, Q.Title, Q.CreationDate, Q.Score, Q.ViewCount, Q.OwnerUserId, Q.AnswerCount, Q.LastActivityDate, Q.Tags
),
QuestionTagBreakdown AS (
    -- Splits the 'Tags' string into individual tag names for each question
    SELECT
        PQM.QuestionId,
        TRIM(UNNEST(string_to_array(SUBSTRING(PQM.Tags FROM 2 FOR LENGTH(PQM.Tags)-2), '><'))) AS TagName
    FROM PostQualityMetrics PQM
    WHERE PQM.Tags IS NOT NULL AND LENGTH(PQM.Tags) > 2
),
TagAnalysis AS (
    -- Aggregates performance metrics per tag using window functions
    SELECT
        QT.TagName,
        COUNT(DISTINCT QT.QuestionId) AS TagUseCount,
        SUM(PQM.QuestionScore) AS TotalQuestionScoreInTag,
        AVG(PQM.ViewCount) AS AvgQuestionViewCountInTag,
        SUM(PQM.ActualAnswerCount) AS TotalAnswersInTagQuestions,
        AVG(PQM.AvgAnswerScore) AS AvgAnswerScoreForTagQuestions,
        SUM(CASE WHEN PQM.HasAcceptedAnswer > 0 THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswers,
        COUNT(B.Id) AS BadgesAwardedForTag,
        RANK() OVER (ORDER BY COUNT(DISTINCT QT.QuestionId) DESC, AVG(PQM.ViewCount) DESC) AS TagPopularityRank
    FROM QuestionTagBreakdown QT
    JOIN PostQualityMetrics PQM ON QT.QuestionId = PQM.QuestionId
    LEFT JOIN Badges B ON B.Name = QT.TagName AND B.TagBased = TRUE
    GROUP BY QT.TagName
    HAVING COUNT(DISTINCT QT.QuestionId) > 0 -- Only include tags that are actually used on questions
),
PostHistoryTimeline AS (
    -- Analyzes post lifecycle and moderation actions using window functions
    SELECT
        PH.PostId,
        PH.PostHistoryTypeId,
        PHT.Name AS HistoryTypeName,
        PH.CreationDate AS HistoryDate,
        PH.UserId AS HistoryInitiatorUserId,
        PH.Comment,
        PH.Text,
        LAG(PH.CreationDate) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS PreviousHistoryDate,
        LEAD(PH.CreationDate) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS NextHistoryDate,
        ROW_NUMBER() OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS EventSequence
    FROM PostHistory PH
    JOIN PostHistoryTypes PHT ON PH.PostHistoryTypeId = PHT.Id
    WHERE PH.PostHistoryTypeId IN (
        1,  -- Initial Title
        2,  -- Initial Body
        3,  -- Initial Tags
        4,  -- Edit Title
        5,  -- Edit Body
        6,  -- Edit Tags
        10, -- Post Closed
        11, -- Post Reopened
        12, -- Post Deleted
        13, -- Post Undeleted
        14, -- Post Locked
        15, -- Post Unlocked
        19, -- Question Protected
        20, -- Question Unprotected
        35, -- Post Migrated Away
        36  -- Post Migrated Here
    )
)
SELECT
    UE.UserId,
    UE.DisplayName,
    UE.Reputation,
    UE.YearsActive,
    UE.TotalPosts,
    UE.TotalQuestions,
    UE.TotalAnswers,
    UE.TotalComments,
    UE.TotalPostScoreReceived,
    UE.TotalBadges,
    UE.AvgPostScore,
    UE.PostsClosedByOthers,
    UE.PostsReopenedByOthers,
    (UE.UpVotes - UE.DownVotes) AS NetVotesGivenByOthers,
    PQM.QuestionTitle,
    PQM.QuestionCreationDate,
    PQM.QuestionScore,
    PQM.ViewCount,
    PQM.ActualAnswerCount,
    PQM.AvgAnswerScore,
    PQM.MaxAnswerScore,
    PQM.HasAcceptedAnswer,
    PQM.LinkedPostsCount,
    PQM.DuplicatePostsCount,
    PQM.DaysActive AS QuestionDaysActive,
    EXTRACT(EPOCH FROM (NOW() - PQM.LastContentEditDate)) / (60 * 60 * 24) AS DaysSinceLastContentEdit,
    TA.TagName,
    TA.TagUseCount,
    TA.AvgQuestionViewCountInTag,
    TA.TagPopularityRank,
    (TA.TotalQuestionScoreInTag / NULLIF(TA.TagUseCount, 0)) AS AvgQuestionScorePerTag,
    PHTL_FirstEdit.HistoryDate AS FirstEditDate,
    PHTL_LastClose.HistoryDate AS LastCloseDate,
    PHTL_LastReopen.HistoryDate AS LastReopenDate,
    -- Complicated calculation/expression involving NULL logic and string operations for categorization
    CASE
        WHEN PQM.QuestionScore >= 100 AND PQM.ActualAnswerCount >= 5 AND PQM.HasAcceptedAnswer > 0 THEN 'High-Impact Question'
        WHEN PQM.QuestionScore >= 50 AND PQM.ActualAnswerCount >= 2 THEN 'Good Question'
        WHEN PQM.QuestionScore > 0 AND PQM.ActualAnswerCount > 0 THEN 'Engaged Question'
        WHEN PQM.QuestionScore IS NULL OR PQM.QuestionScore <= 0 THEN COALESCE('Low-Score/Unanswered Question' ||
            CASE WHEN PQM.DeclaredAnswerCount = 0 THEN ' (No Answers Declared)' ELSE '' END ||
            CASE WHEN PQM.EffectiveAnswerCount = 0 THEN ' (No Effective Answers)' ELSE '' END, 'No Info')
        ELSE 'Other'
    END AS QuestionCategory,
    -- Correlated subquery: counts old close votes
    (
        SELECT COUNT(DISTINCT PH_Close_Inner.PostId)
        FROM PostHistory PH_Close_Inner
        WHERE PH_Close_Inner.PostId = PQM.QuestionId
          AND PH_Close_Inner.PostHistoryTypeId = 10 -- Post Closed
          AND PH_Close_Inner.CreationDate < NOW() - INTERVAL '30 days'
    ) AS OldClosedCount,
    -- NULL logic: provides the most recent moderation action date
    COALESCE(PHTL_LastClose.HistoryDate, PHTL_LastReopen.HistoryDate) AS LastModerationActionDate,
    -- String aggregation and NULL handling for recent editors
    (
        SELECT
            STRING_AGG(DISTINCT SUBSTRING(COALESCE(U_Editor.DisplayName, PH_Editors.UserDisplayName) FROM 1 FOR 15), ', ')
        FROM PostHistory PH_Editors
        LEFT JOIN Users U_Editor ON PH_Editors.UserId = U_Editor.Id
        WHERE PH_Editors.PostId = PQM.QuestionId
          AND PH_Editors.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Body, Tags
        GROUP BY PH_Editors.PostId
    ) AS RecentEditorsList
FROM UserEngagement UE
LEFT JOIN PostQualityMetrics PQM ON UE.UserId = PQM.OwnerUserId
-- Joins questions to tags via the breakdown CTE
LEFT JOIN QuestionTagBreakdown QTB_Main ON PQM.QuestionId = QTB_Main.QuestionId
LEFT JOIN TagAnalysis TA ON QTB_Main.TagName = TA.TagName
-- Joins for specific post history events, using the timeline CTE
LEFT JOIN PostHistoryTimeline PHTL_FirstEdit ON PHTL_FirstEdit.PostId = PQM.QuestionId
    AND PHTL_FirstEdit.PostHistoryTypeId IN (4, 5, 6)
    AND PHTL_FirstEdit.EventSequence = 1 -- Only the very first edit
LEFT JOIN (
    SELECT PostId, MAX(HistoryDate) AS HistoryDate
    FROM PostHistoryTimeline
    WHERE PostHistoryTypeId = 10
    GROUP BY PostId
) AS PHTL_LastClose ON PHTL_LastClose.PostId = PQM.QuestionId
LEFT JOIN (
    SELECT PostId, MAX(HistoryDate) AS HistoryDate
    FROM PostHistoryTimeline
    WHERE PostHistoryTypeId = 11
    GROUP BY PostId
) AS PHTL_LastReopen ON PHTL_LastReopen.PostId = PQM.QuestionId
WHERE UE.Reputation >= 1000 -- Filter for users with significant reputation
  AND PQM.QuestionId IS NOT NULL -- Only include users who own at least one question
  AND PQM.ViewCount > 50 -- Only include questions with some views
ORDER BY UE.Reputation DESC, PQM.QuestionCreationDate DESC, PQM.QuestionScore DESC
LIMIT 1000;
