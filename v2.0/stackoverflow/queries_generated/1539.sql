-- {"query": "1539.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3368} 

WITH UserPostStats AS (
    -- Aggregate basic user statistics related to posts and votes
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestionsPosted,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswersPosted,
        SUM(CASE WHEN V_Received.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesReceivedOnPosts,
        SUM(CASE WHEN V_Received.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesReceivedOnPosts,
        SUM(CASE WHEN V_Given.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesGiven,
        SUM(CASE WHEN V_Given.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesGiven
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Votes V_Received ON P.Id = V_Received.PostId AND V_Received.VoteTypeId IN (2, 3) -- Up/Down votes received on their posts
    LEFT JOIN Votes V_Given ON U.Id = V_Given.UserId AND V_Given.VoteTypeId IN (2, 3) -- Up/Down votes given by user
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
),
PostTimeline AS (
    -- Extract specific post history events for timeline analysis
    SELECT
        PH.PostId,
        PH.PostHistoryTypeId,
        PH.CreationDate AS EventDate,
        PH.UserId AS EventUserId,
        COALESCE(PH.Comment, '') AS EventComment,
        -- Window function: Calculate the previous event date within each post's history
        LAG(PH.CreationDate, 1, PH.CreationDate) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS PrevEventDate
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (
        1,  -- Initial Title
        2,  -- Initial Body
        4,  -- Edit Title
        5,  -- Edit Body
        6,  -- Edit Tags
        10, -- Post Closed
        11, -- Post Reopened
        12, -- Post Deleted
        13  -- Post Undeleted
    )
),
PostMetrics AS (
    -- Aggregate detailed metrics for posts, including edit, close, and reopen counts
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.Title,
        P.Tags,
        SUM(CASE WHEN PT.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS TotalEdits,
        COUNT(DISTINCT CASE WHEN PT.PostHistoryTypeId IN (4, 5, 6) THEN PT.EventUserId END) AS DistinctEditors,
        MAX(CASE WHEN PT.PostHistoryTypeId = 10 THEN PT.EventDate END) AS LastCloseDate,
        MIN(CASE WHEN PT.PostHistoryTypeId = 11 THEN PT.EventDate END) AS FirstReopenDate,
        -- Correlated subquery to find the initial close reason ID
        COALESCE(
            (SELECT CAST(SUBSTRING(PH_CR.Comment FROM '^[0-9]+') AS SMALLINT)
             FROM PostHistory PH_CR
             WHERE PH_CR.PostId = P.Id
               AND PH_CR.PostHistoryTypeId = 10
             ORDER BY PH_CR.CreationDate ASC
             LIMIT 1),
            NULL
        ) AS InitialCloseReasonId,
        -- Calculate time from initial post creation to the first close event in hours
        EXTRACT(EPOCH FROM (MIN(CASE WHEN PT.PostHistoryTypeId = 10 THEN PT.EventDate END) - P.CreationDate)) / 3600 AS HoursToFirstClose,
        COUNT(CASE WHEN PT.PostHistoryTypeId = 10 THEN 1 END) AS CloseCount,
        COUNT(CASE WHEN PT.PostHistoryTypeId = 11 THEN 1 END) AS ReopenCount
    FROM Posts P
    LEFT JOIN PostTimeline PT ON P.Id = PT.PostId
    WHERE P.PostTypeId IN (1, 2) -- Focus on Questions (1) and Answers (2)
    GROUP BY P.Id, P.PostTypeId, P.OwnerUserId, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount, P.CommentCount, P.FavoriteCount, P.Title, P.Tags
),
PostTagMap AS (
    -- Map posts to individual tags for easier joining
    SELECT
        PM.PostId,
        TRIM(UNNEST(string_to_array(SUBSTRING(PM.Tags FROM 2 FOR LENGTH(PM.Tags) - 2), '><'))) AS TagName
    FROM PostMetrics PM
    WHERE PM.Tags IS NOT NULL AND PM.Tags != ''
),
TagDifficultyRank AS (
    -- Rank tags based on average time to close, distinct editors, and close ratio
    SELECT
        PTM.TagName,
        AVG(PM.HoursToFirstClose) AS AvgHoursToFirstClose,
        AVG(PM.DistinctEditors) AS AvgDistinctEditorsPerPost,
        CAST(SUM(CASE WHEN PM.CloseCount > 0 THEN 1 ELSE 0 END) AS NUMERIC) / COUNT(PM.PostId) AS CloseRatio,
        COUNT(DISTINCT PM.PostId) AS PostsWithTagCount,
        -- Window function: Rank tags by their "difficulty" metrics
        DENSE_RANK() OVER (ORDER BY AVG(PM.HoursToFirstClose) DESC, AVG(PM.DistinctEditors) DESC, (CAST(SUM(CASE WHEN PM.CloseCount > 0 THEN 1 ELSE 0 END) AS NUMERIC) / COUNT(PM.PostId)) DESC) AS TagDifficultyRank
    FROM PostMetrics PM
    INNER JOIN PostTagMap PTM ON PM.PostId = PTM.PostId
    WHERE PM.PostTypeId = 1 -- Only consider tags from questions
    GROUP BY PTM.TagName
    HAVING COUNT(DISTINCT PM.PostId) >= 50 -- Only consider tags with at least 50 posts for meaningful statistics
),
ProblematicPostQualifier AS (
    -- Categorize posts based on their problematic characteristics
    SELECT
        PM.PostId,
        PM.OwnerUserId,
        PM.PostCreationDate,
        PM.PostScore,
        PM.ViewCount,
        PM.AnswerCount,
        PM.Title,
        PM.Tags,
        PM.TotalEdits,
        PM.DistinctEditors,
        PM.LastCloseDate,
        PM.FirstReopenDate,
        PM.InitialCloseReasonId,
        PM.HoursToFirstClose,
        PM.CloseCount,
        PM.ReopenCount,
        CR.Name AS CloseReasonName,
        -- Complex CASE expression for categorizing problematic posts
        CASE
            WHEN PM.CloseCount > 0 AND PM.ReopenCount > 0 AND PM.TotalEdits >= 5 THEN 'Highly Controversial'
            WHEN PM.CloseCount > 1 AND PM.TotalEdits >= 3 THEN 'Repeatedly Closed/Edited'
            WHEN PM.TotalEdits >= 10 THEN 'Heavily Edited'
            WHEN PM.HoursToFirstClose IS NOT NULL AND PM.HoursToFirstClose <= 24 THEN 'Quickly Closed'
            ELSE 'Moderately Problematic'
        END AS ProblematicCategory
    FROM PostMetrics PM
    LEFT JOIN CloseReasonTypes CR ON PM.InitialCloseReasonId = CR.Id
    WHERE PM.TotalEdits > 0 OR PM.CloseCount > 0 OR PM.ReopenCount > 0
),
UserContributionSummary AS (
    -- Summarize user contributions, especially in relation to problematic posts and difficult tags
    SELECT
        UPS.UserId,
        UPS.DisplayName,
        UPS.Reputation,
        UPS.UserCreationDate,
        UPS.LastAccessDate,
        UPS.TotalQuestionsPosted,
        UPS.TotalAnswersPosted,
        UPS.TotalUpvotesReceivedOnPosts,
        UPS.TotalDownvotesReceivedOnPosts,
        UPS.TotalUpvotesGiven,
        UPS.TotalDownvotesGiven,
        -- Calculate average reputation gain per active day, handling potential division by zero with NULLIF
        CAST(UPS.Reputation AS NUMERIC) / NULLIF(EXTRACT(DAY FROM (UPS.LastAccessDate - UPS.UserCreationDate)), 0) AS AvgReputationPerDayActive,
        COUNT(DISTINCT PPQ_Owned.PostId) AS ProblematicPostsOwnedCount,
        SUM(COALESCE(PPQ_Owned.TotalEdits, 0)) AS TotalEditsOnOwnedProblematicPosts,
        SUM(COALESCE(PPQ_Owned.CloseCount, 0)) AS TotalCloseEventsOnOwnedPosts,
        SUM(COALESCE(PPQ_Owned.ReopenCount, 0)) AS TotalReopenEventsOnOwnedPosts,
        -- Correlated subquery to count problematic posts edited by the user (not as owner)
        COALESCE(
            (SELECT COUNT(DISTINCT PT_Edit.PostId)
             FROM PostTimeline PT_Edit
             INNER JOIN ProblematicPostQualifier PPQ_Editor ON PT_Edit.PostId = PPQ_Editor.PostId
             WHERE PT_Edit.EventUserId = UPS.UserId AND PT_Edit.PostHistoryTypeId IN (4, 5, 6)
               AND PT_Edit.PostId NOT IN (SELECT PostId FROM ProblematicPostQualifier WHERE OwnerUserId = UPS.UserId) -- Exclude their own posts
            ), 0
        ) AS ProblematicPostsEditedByOthersCount,
        -- Correlated subquery to count user's close/reopen votes on problematic posts
        COALESCE(
            (SELECT SUM(CASE WHEN PH_Action.PostHistoryTypeId = 10 THEN 1 ELSE 0 END)
             FROM PostHistory PH_Action
             WHERE PH_Action.UserId = UPS.UserId
               AND PH_Action.PostHistoryTypeId IN (10, 11)
               AND PH_Action.PostId IN (SELECT PostId FROM ProblematicPostQualifier)
            ), 0
        ) AS TimesVotedOnProblematicPosts,
        SUM(CASE WHEN TDR.TagName IS NOT NULL AND TDR.TagDifficultyRank <= 10 THEN 1 ELSE 0 END) AS ContributionsToTop10DifficultTags
    FROM UserPostStats UPS
    LEFT JOIN ProblematicPostQualifier PPQ_Owned ON UPS.UserId = PPQ_Owned.OwnerUserId
    LEFT JOIN PostTagMap PTM ON PPQ_Owned.PostId = PTM.PostId
    LEFT JOIN TagDifficultyRank TDR ON PTM.TagName = TDR.TagName
    GROUP BY
        UPS.UserId, UPS.DisplayName, UPS.Reputation, UPS.UserCreationDate, UPS.LastAccessDate,
        UPS.TotalQuestionsPosted, UPS.TotalAnswersPosted, UPS.TotalUpvotesReceivedOnPosts,
        UPS.TotalDownvotesReceivedOnPosts, UPS.TotalUpvotesGiven, UPS.TotalDownvotesGiven
    HAVING UPS.Reputation > 500 -- Filter for more experienced users
)
-- Main query part 1: Users who own highly controversial posts
SELECT
    'Owner of Controversial Posts' AS UserCategory,
    UCS.UserId,
    UCS.DisplayName,
    UCS.Reputation,
    UCS.UserCreationDate,
    UCS.LastAccessDate,
    UCS.TotalQuestionsPosted,
    UCS.TotalAnswersPosted,
    UCS.TotalUpvotesReceivedOnPosts,
    UCS.TotalDownvotesReceivedOnPosts,
    UCS.ProblematicPostsOwnedCount,
    UCS.TotalEditsOnOwnedProblematicPosts,
    UCS.TotalCloseEventsOnOwnedPosts,
    UCS.TotalReopenEventsOnOwnedPosts,
    UCS.ProblematicPostsEditedByOthersCount,
    UCS.TimesVotedOnProblematicPosts,
    UCS.ContributionsToTop10DifficultTags,
    PPQ_Controversial.PostId AS SampleProblematicPostId,
    PPQ_Controversial.Title AS SampleProblematicPostTitle,
    PPQ_Controversial.ProblematicCategory AS SamplePostProblematicCategory,
    PPQ_Controversial.HoursToFirstClose AS SamplePostHoursToFirstClose,
    PPQ_Controversial.CloseReasonName AS SamplePostCloseReason
FROM UserContributionSummary UCS
INNER JOIN ProblematicPostQualifier PPQ_Controversial
    ON UCS.UserId = PPQ_Controversial.OwnerUserId
    AND PPQ_Controversial.ProblematicCategory = 'Highly Controversial'
WHERE UCS.ProblematicPostsOwnedCount > 0
ORDER BY UCS.Reputation DESC, UCS.ProblematicPostsOwnedCount DESC
LIMIT 100 -- Limit to top 100 users in this category

UNION ALL

-- Main query part 2: Users who are active in moderating/editing problematic posts (not necessarily owners)
SELECT
    'Active Moderator/Editor of Problematic Posts' AS UserCategory,
    UCS.UserId,
    UCS.DisplayName,
    UCS.Reputation,
    UCS.UserCreationDate,
    UCS.LastAccessDate,
    UCS.TotalQuestionsPosted,
    UCS.TotalAnswersPosted,
    UCS.TotalUpvotesReceivedOnPosts,
    UCS.TotalDownvotesReceivedOnPosts,
    UCS.ProblematicPostsOwnedCount,
    UCS.TotalEditsOnOwnedProblematicPosts,
    UCS.TotalCloseEventsOnOwnedPosts,
    UCS.TotalReopenEventsOnOwnedPosts,
    UCS.ProblematicPostsEditedByOthersCount,
    UCS.TimesVotedOnProblematicPosts,
    UCS.ContributionsToTop10DifficultTags,
    NULL AS SampleProblematicPostId, -- Not directly tied to a specific owned post for this category
    NULL AS SampleProblematicPostTitle,
    NULL AS SamplePostProblematicCategory,
    NULL AS SamplePostHoursToFirstClose,
    NULL AS SamplePostCloseReason
FROM UserContributionSummary UCS
WHERE UCS.ProblematicPostsEditedByOthersCount > 0 OR UCS.TimesVotedOnProblematicPosts > 0
ORDER BY UCS.Reputation DESC, (UCS.ProblematicPostsEditedByOthersCount + UCS.TimesVotedOnProblematicPosts) DESC
LIMIT 100; -- Limit to top 100 users in this category
