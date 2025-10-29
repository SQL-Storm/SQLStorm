-- {"query": "1046.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2836} 
WITH UserStats AS (
    -- Aggregates user-specific metrics including total posts, comments, vote activity, and badge statistics.
    -- Uses COALESCE for NULL safety in sums and MAX(GREATEST(...)) for determining the last user activity across different tables.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COUNT(C.Id) AS TotalComments,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScore,
        SUM(CASE WHEN V.VoteTypeId IN (2, 8, 9, 15) THEN 1 ELSE 0 END) AS UpVotesGiven, -- UpMod, BountyStart, BountyClose, ModeratorReview
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
        MAX(GREATEST(COALESCE(P.LastActivityDate, '1900-01-01'::timestamp), COALESCE(C.CreationDate, '1900-01-01'::timestamp), U.LastAccessDate)) AS LastUserActivity,
        AVG(CASE WHEN P.PostTypeId IN (1, 2) THEN P.Score END) AS AvgPostScore,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        U.AboutMe -- Including AboutMe here to prevent an additional join to Users later just for this column
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V ON U.Id = V.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.AboutMe
),
PostDetailedMetrics AS (
    -- Calculates detailed metrics for questions, including answer statistics, close history, linked/duplicate posts,
    -- and uses window functions for ranking and percentiles. It also safely extracts the first tag using string functions.
    SELECT
        P.Id AS PostId,
        P.Title,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.FavoriteCount,
        P.OwnerUserId,
        P.LastActivityDate,
        P.ClosedDate,
        CASE
            WHEN P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2 THEN SPLIT_PART(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags)-2), '><', 1)
            ELSE NULL
        END AS FirstTag, -- Extracts the first tag from the '<tag1><tag2>' string format
        COUNT(DISTINCT Ans.Id) AS ActualAnswerCount,
        SUM(COALESCE(Ans.Score, 0)) AS TotalAnswerScore,
        AVG(Ans.Score) FILTER (WHERE Ans.Score IS NOT NULL) AS AvgAnswerScore,
        MAX(PH_Close.CreationDate) AS LastCloseDate,
        (SELECT COUNT(DISTINCT PL_Linked.RelatedPostId) FROM PostLinks PL_Linked WHERE PL_Linked.PostId = P.Id AND PL_Linked.LinkTypeId = 1) AS LinkedPostsCount,
        (SELECT COUNT(DISTINCT PL_Duplicate.RelatedPostId) FROM PostLinks PL_Duplicate WHERE PL_Duplicate.PostId = P.Id AND PL_Duplicate.LinkTypeId = 3) AS DuplicatePostsCount,
        RANK() OVER (PARTITION BY P.OwnerUserId ORDER BY P.ViewCount DESC, P.Id DESC) AS RankByViewsForUser, -- Ranks user's questions by view count
        NTILE(100) OVER (ORDER BY P.Score DESC, P.Id DESC) AS ScorePercentile, -- Assigns a percentile rank based on post score
        P.Tags -- Keep original Tags string for later string expression calculation
    FROM Posts P
    LEFT JOIN Posts Ans ON P.Id = Ans.ParentId AND Ans.PostTypeId = 2 -- Joins to find answers to the question
    LEFT JOIN PostHistory PH_Close ON P.Id = PH_Close.PostId AND PH_Close.PostHistoryTypeId = 10 -- Finds closure events
    WHERE P.PostTypeId = 1 -- Focus only on questions
    GROUP BY
        P.Id, P.Title, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount,
        P.FavoriteCount, P.OwnerUserId, P.LastActivityDate, P.ClosedDate, P.Tags
),
RecentPostHistory AS (
    -- Identifies the most recent history event of specific types for each post.
    -- Uses ROW_NUMBER window function to pick the latest entry for each post and history type.
    SELECT
        PH.PostId,
        PH.PostHistoryTypeId,
        PH.CreationDate AS HistoryDate,
        PH.Comment,
        PH.Text AS HistoryText,
        ROW_NUMBER() OVER (PARTITION BY PH.PostId, PH.PostHistoryTypeId ORDER BY PH.CreationDate DESC, PH.Id DESC) AS rn
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (4, 5, 6, 10, 11, 12, 13, 19, 20, 35) -- Common post history types for edits, close/reopen, delete/undelete, protect/unprotect, migration
)
SELECT
    US.UserId,
    US.DisplayName,
    US.Reputation,
    US.UserCreationDate,
    US.LastAccessDate,
    US.TotalPosts,
    US.TotalQuestions,
    US.TotalAnswers,
    US.TotalComments,
    US.TotalPostScore,
    US.UpVotesGiven,
    US.DownVotesGiven,
    US.LastUserActivity,
    COALESCE(US.AvgPostScore, 0.0) AS AvgPostScore, -- Ensures a 0.0 value if no posts exist for average calculation
    US.TotalBadges,
    US.GoldBadges,
    SUM(PDM.PostScore) AS TotalQuestionScore,
    AVG(PDM.ViewCount) AS AvgQuestionViews,
    COUNT(PDM.PostId) AS NumberOfQuestions,
    SUM(CASE WHEN PDM.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS ClosedQuestionsCount,
    MAX(PDM.LastCloseDate) AS UserLatestQuestionCloseDate,
    SUM(PDM.DuplicatePostsCount) AS TotalDuplicatesCreated,
    AVG(PDM.ActualAnswerCount) AS AvgActualAnswersPerQuestion,
    MAX(CASE WHEN PDM.ScorePercentile <= 10 THEN 1 ELSE 0 END) AS HasTop10PercentileQuestion, -- Binary flag: 1 if user has at least one question in the top 10% by score
    STRING_AGG(DISTINCT PDM.FirstTag, ', ') FILTER (WHERE PDM.FirstTag IS NOT NULL AND PDM.FirstTag != '') AS UserTopTags, -- Aggregates distinct first tags used by the user
    -- Correlated Subquery: Retrieves the body text of the latest edit for the user's highest viewed question.
    (
        SELECT RPH_Body.HistoryText
        FROM RecentPostHistory RPH_Body
        WHERE RPH_Body.PostId = (
            SELECT PDM_MaxView.PostId
            FROM PostDetailedMetrics PDM_MaxView
            WHERE PDM_MaxView.OwnerUserId = US.UserId AND PDM_MaxView.RankByViewsForUser = 1
            ORDER BY PDM_MaxView.PostId DESC -- Added for deterministic pick in case of ties
            LIMIT 1
        )
        AND RPH_Body.PostHistoryTypeId = 5 -- Represents 'Edit Body'
        AND RPH_Body.rn = 1
    ) AS LatestBodyEditOfHighestViewedQuestion,
    -- Correlated Subquery: Retrieves the name of the close reason for the user's most recently closed question.
    (
        SELECT CR.Name
        FROM RecentPostHistory RPH_CloseReason
        LEFT JOIN CloseReasonTypes CR ON RPH_CloseReason.Comment::smallint = CR.Id -- Type cast needed to join Comment (varchar) with Id (smallint)
        WHERE RPH_CloseReason.PostId = (
            SELECT PDM_MaxClose.PostId
            FROM PostDetailedMetrics PDM_MaxClose
            WHERE PDM_MaxClose.OwnerUserId = US.UserId AND PDM_MaxClose.ClosedDate IS NOT NULL
            ORDER BY PDM_MaxClose.ClosedDate DESC, PDM_MaxClose.PostId DESC -- Added for deterministic pick in case of ties
            LIMIT 1
        )
        AND RPH_CloseReason.PostHistoryTypeId = 10 -- Represents 'Post Closed'
        AND RPH_CloseReason.rn = 1
    ) AS LatestCloseReasonName,
    -- Complex Calculation: A 'User Engagement Score' derived from various user attributes.
    (US.Reputation::numeric / 100.0) + (US.TotalPosts * 0.5) + (US.TotalComments * 0.1) + (US.GoldBadges * 10) + (US.UpVotesGiven * 0.05) - (US.DownVotesGiven * 0.1) AS UserEngagementScore,
    -- Complicated Predicate/NULL Logic: Categorizes users based on question activity and content within their 'AboutMe' text.
    CASE
        WHEN US.TotalQuestions > 0 AND COALESCE(US.AboutMe, '') LIKE '%<p>developer</p>%' THEN 'Active HTML Developer' -- Checks for a specific HTML snippet in AboutMe
        WHEN US.TotalQuestions > 0 AND US.AboutMe IS NOT NULL AND LENGTH(US.AboutMe) > 500 THEN 'Verbose Contributor'
        WHEN US.TotalQuestions > 0 AND US.AboutMe IS NOT NULL THEN 'Active Contributor'
        WHEN US.TotalPosts > 0 THEN 'General Contributor'
        ELSE 'Passive User'
    END AS UserCategory,
    -- Set Operator Usage: Counts questions owned by the user that have been both edited (title, body, or tags) AND closed.
    (
        SELECT COUNT(DISTINCT EditedAndClosed.PostId)
        FROM (
            SELECT RPH_Edit.PostId FROM RecentPostHistory RPH_Edit WHERE RPH_Edit.PostHistoryTypeId IN (4,5,6) AND RPH_Edit.rn = 1 -- Edited (Title, Body, Tags)
            INTERSECT -- Set operator to find common PostIds
            SELECT RPH_Close.PostId FROM RecentPostHistory RPH_Close WHERE RPH_Close.PostHistoryTypeId = 10 AND RPH_Close.rn = 1 -- Closed
        ) AS EditedAndClosed
        WHERE EditedAndClosed.PostId IN (SELECT PDM_Filtered.PostId FROM PostDetailedMetrics PDM_Filtered WHERE PDM_Filtered.OwnerUserId = US.UserId)
    ) AS EditedAndClosedQuestionsCount,
    -- Advanced String Expression: Calculates the average length of the full 'Tags' string, but only for posts identified as having multiple tags.
    AVG(LENGTH(PDM.Tags)) FILTER (WHERE PDM.Tags LIKE '<%>%<>%') AS AvgMultiTagLength
FROM UserStats US
LEFT JOIN PostDetailedMetrics PDM ON US.UserId = PDM.OwnerUserId
GROUP BY
    US.UserId, US.DisplayName, US.Reputation, US.UserCreationDate, US.LastAccessDate,
    US.TotalPosts, US.TotalQuestions, US.TotalAnswers, US.TotalComments, US.TotalPostScore,
    US.UpVotesGiven, US.DownVotesGiven, US.LastUserActivity, US.AvgPostScore, US.TotalBadges,
    US.GoldBadges, US.AboutMe
ORDER BY UserEngagementScore DESC, US.Reputation DESC
LIMIT 1000;