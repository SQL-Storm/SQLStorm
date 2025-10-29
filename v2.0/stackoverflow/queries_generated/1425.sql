-- {"query": "1425.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3849} 

WITH UserEngagement AS (
    -- CTE 1: Summarizes user activity, including post and comment counts, and calculates average scores.
    -- Uses LEFT JOIN to include users with no posts/comments.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Views AS UserViews,
        U.UpVotes AS UserUpVotes,
        U.DownVotes AS UserDownVotes,
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestionsOwned,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswersOwned,
        SUM(CASE WHEN P.PostTypeId IN (1, 2) THEN P.Score ELSE 0 END) AS TotalPostScore,
        AVG(CASE WHEN P.PostTypeId IN (1, 2) THEN P.Score ELSE NULL END) AS AvgPostScore,
        MAX(P.LastActivityDate) AS LastPostActivity,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        SUM(C.Score) AS TotalCommentScore,
        MAX(C.CreationDate) AS LastCommentActivity,
        COALESCE(MAX(P.LastActivityDate), MAX(C.CreationDate), U.LastAccessDate) AS OverallLastActivity
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.UpVotes, U.DownVotes
),
PostEditActivity AS (
    -- CTE 2: Calculates various edit-related metrics for posts, highlighting actively managed content.
    -- Uses a correlated subquery to check for specific history types within a recent period.
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.ViewCount,
        P.Score AS PostScore,
        P.AcceptedAnswerId,
        P.PostTypeId,
        COUNT(DISTINCT PH_Edit.Id) AS EditCount,
        COUNT(DISTINCT CASE WHEN PH_Edit.PostHistoryTypeId IN (7, 8, 9) THEN PH_Edit.Id END) AS RollbackCount,
        COUNT(DISTINCT CASE WHEN PH_Edit.PostHistoryTypeId = 10 THEN PH_Edit.Id END) AS CloseCount,
        COUNT(DISTINCT CASE WHEN PH_Edit.PostHistoryTypeId = 11 THEN PH_Edit.Id END) AS ReopenCount,
        MAX(PH_Edit.CreationDate) AS LastEditDate,
        NULLIF(COUNT(DISTINCT CASE WHEN PH_Edit.PostHistoryTypeId IN (4, 5, 6) THEN PH_Edit.Id END), 0) AS ActualEditCount,
        (SELECT MAX(PH_Inner.CreationDate)
         FROM PostHistory AS PH_Inner
         WHERE PH_Inner.PostId = P.Id
           AND PH_Inner.PostHistoryTypeId IN (1, 2, 3)
           AND PH_Inner.CreationDate < P.CreationDate + INTERVAL '1 hour'
        ) AS InitialHistoryTimestamp
    FROM Posts AS P
    LEFT JOIN PostHistory AS PH_Edit ON P.Id = PH_Edit.PostId
    WHERE P.PostTypeId IN (1, 2) -- Focus on Questions and Answers
    GROUP BY P.Id, P.OwnerUserId, P.CreationDate, P.ViewCount, P.Score, P.AcceptedAnswerId, P.PostTypeId
),
PostTagsExpanded AS (
    -- Helper CTE to expand the Tags string into individual rows using string_to_array and UNNEST.
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.Score,
        P.ViewCount,
        TRIM(UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><'))) AS TagName
    FROM Posts AS P
    WHERE P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2 AND P.PostTypeId = 1
),
TopTagsAndUsers AS (
    -- CTE 3: Identifies popular tags and users associated with them.
    -- Uses expanded tags and a window function to rank tags by view count and post count.
    SELECT
        PTE.TagName,
        T.Id AS TagId,
        SUM(PTE.ViewCount) AS TotalTagViewCount,
        COUNT(PTE.PostId) AS TotalPostsWithTag,
        AVG(PTE.Score) AS AvgTagPostScore,
        ROW_NUMBER() OVER (ORDER BY SUM(PTE.ViewCount) DESC, COUNT(PTE.PostId) DESC) AS TagRank
    FROM PostTagsExpanded AS PTE
    JOIN Tags AS T ON PTE.TagName = T.TagName
    GROUP BY PTE.TagName, T.Id
    HAVING COUNT(PTE.PostId) > 50 -- Only consider tags with significant usage
),
DuplicateLinkAnalysis AS (
    -- CTE 4: Analyzes potential duplicate post chains (second-degree duplicates).
    SELECT
        PL1.PostId AS OriginalPostId,
        PL2.RelatedPostId AS UltimateDuplicateId,
        COUNT(DISTINCT PL2.Id) AS DuplicateChainLength
    FROM PostLinks AS PL1
    JOIN PostLinks AS PL2 ON PL1.RelatedPostId = PL2.PostId
    WHERE PL1.LinkTypeId = 3 -- Duplicate
      AND PL2.LinkTypeId = 3 -- Duplicate
      AND PL1.PostId != PL2.RelatedPostId -- Ensure not a direct self-link via chain
    GROUP BY PL1.PostId, PL2.RelatedPostId
    HAVING COUNT(DISTINCT PL2.Id) > 1
),
RankedAnswers AS (
    -- CTE 5: Ranks answers for each question by score and creation date.
    -- Uses a window function to find the best answers.
    SELECT
        A.Id AS AnswerId,
        A.ParentId AS QuestionId,
        A.OwnerUserId AS AnswererUserId,
        A.Score AS AnswerScore,
        A.CreationDate AS AnswerCreationDate,
        ROW_NUMBER() OVER (PARTITION BY A.ParentId ORDER BY A.Score DESC, A.CreationDate ASC) AS AnswerRank
    FROM Posts AS A
    WHERE A.PostTypeId = 2
),
UserBadgeActivity AS (
    -- CTE 6: Summarizes user badge activity, especially recent gold/silver badges.
    -- Uses NTILE for a percentile-like distribution of users based on badge count.
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        COUNT(CASE WHEN B.Class = 1 THEN B.Id END) AS GoldBadges,
        COUNT(CASE WHEN B.Class = 2 THEN B.Id END) AS SilverBadges,
        COUNT(CASE WHEN B.Date > CURRENT_DATE - INTERVAL '1 year' THEN B.Id END) AS RecentBadges,
        NTILE(10) OVER (ORDER BY COUNT(B.Id) DESC) AS BadgeCountDecile
    FROM Badges AS B
    GROUP BY B.UserId
),
AdvancedPostMetrics AS (
    -- CTE 7: Further enriches post data with aggregated metrics from comments and history.
    -- Demonstrates complex calculations and NULL handling.
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.CreationDate,
        P.ClosedDate,
        COALESCE(P.ContentLicense, 'Unknown_License') AS EffectiveLicense,
        SUM(COALESCE(C.Score, 0)) AS TotalCommentScoresOnPost,
        AVG(EXTRACT(EPOCH FROM (C.CreationDate - P.CreationDate))) AS AvgCommentTimeSincePost, -- in seconds
        MAX(CASE WHEN PH.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105) THEN PH.CreationDate ELSE NULL END) AS LastClosureEvent,
        MAX(CASE WHEN PH.Comment IS NOT NULL AND PH.Comment LIKE '%off-topic%' THEN 1 ELSE 0 END) AS HadOffTopicCloseReason
    FROM Posts AS P
    LEFT JOIN Comments AS C ON P.Id = C.PostId
    LEFT JOIN PostHistory AS PH ON P.Id = PH.PostId AND PH.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105, 11) -- Closure/Reopen events
    GROUP BY P.Id, P.OwnerUserId, P.Score, P.ViewCount, P.AnswerCount, P.CommentCount, P.FavoriteCount, P.CreationDate, P.ClosedDate, P.ContentLicense
)
-- Main Query: Combines all CTEs to find "High-Impact Users" and their associated posts/metrics.
-- Incorporates window functions, complex predicates, and set operations.
SELECT
    UE.UserId,
    UE.DisplayName,
    UE.Reputation,
    UE.TotalPostsOwned,
    UE.TotalQuestionsOwned,
    UE.TotalAnswersOwned,
    UE.AvgPostScore,
    UE.OverallLastActivity,
    PA.Id AS HighestScoringAnswerId,
    PA.Score AS HighestScoringAnswerScore,
    RA.AnswerRank,
    TS.TagName AS MostFrequentTag,
    TS.TotalTagViewCount AS MostFrequentTagViews,
    UB.GoldBadges,
    UB.RecentBadges,
    UB.BadgeCountDecile,
    APM.TotalCommentScoresOnPost AS TopAnswerCommentScore,
    APM.AvgCommentTimeSincePost AS TopAnswerAvgCommentTime,
    APM.HadOffTopicCloseReason AS HadOffTopicFlagOnTopAnswer,
    SUM(PEA.EditCount) OVER (PARTITION BY UE.UserId) AS UserTotalEdits,
    AVG(PEA.PostScore) OVER (PARTITION BY UE.UserId) AS UserAvgPostScoreOverall,
    RANK() OVER (ORDER BY UE.Reputation DESC, UE.TotalPostScore DESC) AS OverallUserRank,
    CASE
        WHEN UE.Reputation > 50000 AND UE.AvgPostScore > 10 THEN 'Elite Contributor'
        WHEN UB.GoldBadges > 2 OR UB.RecentBadges > 5 THEN 'Recognized Expert'
        WHEN UE.TotalAnswersOwned > 50 AND UE.TotalPostScore > 500 THEN 'Prolific Answerer'
        ELSE 'Active Participant'
    END AS UserCategory,
    -- Correlated subquery: Check if user has posts linked as duplicates.
    EXISTS (
        SELECT 1
        FROM DuplicateLinkAnalysis AS DLA
        WHERE DLA.OriginalPostId = PEA.PostId AND PEA.OwnerUserId = UE.UserId
    ) AS HasDuplicateSourcePost,
    REPLACE(TRIM(SUBSTRING(UE.DisplayName, 1, 10)), ' ', '_') || '_' || UPPER(LEFT(COALESCE(UE.Location, 'Unknown'), 3)) AS UserSignature
FROM UserEngagement AS UE
LEFT JOIN PostEditActivity AS PEA ON UE.UserId = PEA.OwnerUserId
LEFT JOIN RankedAnswers AS RA ON UE.UserId = RA.AnswererUserId AND RA.AnswerRank = 1
LEFT JOIN Posts AS PA ON RA.AnswerId = PA.Id -- Get details for the highest scoring answer
LEFT JOIN (
    SELECT
        PTE.OwnerUserId AS UserId,
        PTE.TagName,
        TTU.TotalTagViewCount,
        ROW_NUMBER() OVER (PARTITION BY PTE.OwnerUserId ORDER BY COUNT(PTE.PostId) DESC, TTU.TotalTagViewCount DESC) AS Rn
    FROM PostTagsExpanded AS PTE
    JOIN TopTagsAndUsers AS TTU ON PTE.TagName = TTU.TagName
    GROUP BY PTE.OwnerUserId, PTE.TagName, TTU.TotalTagViewCount
) AS TS ON UE.UserId = TS.UserId AND TS.Rn = 1 -- Most frequent tag associated with user's questions
LEFT JOIN UserBadgeActivity AS UB ON UE.UserId = UB.UserId
LEFT JOIN AdvancedPostMetrics AS APM ON PA.Id = APM.PostId -- Metrics for the top answer

WHERE UE.TotalPostsOwned > 5
  AND UE.Reputation > 1000
  AND (UE.OverallLastActivity >= CURRENT_DATE - INTERVAL '6 months' OR UE.TotalQuestionsOwned > 10)
  AND (PEA.ActualEditCount IS NULL OR PEA.ActualEditCount > 0) -- Ensure some edits or no post activity recorded
  AND (PA.Score > 5 OR PA.AcceptedAnswerId IS NOT NULL) -- Ensure answers are good or accepted
  AND (UPPER(UE.DisplayName) NOT LIKE '%BOT%' OR UE.DisplayName IS NULL) -- Exclude bots
  AND (UE.UserCreationDate < CURRENT_DATE - INTERVAL '1 year' OR UB.GoldBadges > 0) -- Older users or gold badge holders
ORDER BY OverallUserRank ASC, UE.OverallLastActivity DESC
LIMIT 500

UNION ALL

-- Second part of the query: Focus on posts that are frequently linked as duplicates or have high edit rates,
-- regardless of user activity. This uses a different set of filters and focuses on posts.
SELECT
    NULL AS UserId, -- No specific user focus for this part
    'COMMUNITY_POST_ANALYSIS' AS DisplayName,
    P.Score AS Reputation, -- Re-purpose column for Post Score
    P.AnswerCount AS TotalPostsOwned, -- Re-purpose for Answer Count
    P.ViewCount AS TotalQuestionsOwned, -- Re-purpose for View Count
    PH.EditCount AS TotalAnswersOwned, -- Re-purpose for Edit Count
    PH.RollbackCount AS AvgPostScore, -- Re-purpose for Rollback Count
    P.LastActivityDate AS OverallLastActivity,
    P.Id AS HighestScoringAnswerId, -- Re-purpose for Post Id
    P.Score AS HighestScoringAnswerScore, -- Re-purpose for Post Score
    NULL AS AnswerRank,
    (SELECT PTE_sub.TagName FROM PostTagsExpanded PTE_sub WHERE PTE_sub.PostId = P.Id LIMIT 1) AS MostFrequentTag, -- Simple tag lookup
    TTU_union.TotalTagViewCount AS MostFrequentTagViews,
    NULL AS GoldBadges,
    NULL AS RecentBadges,
    NULL AS BadgeCountDecile,
    APM.TotalCommentScoresOnPost AS TopAnswerCommentScore,
    APM.AvgCommentTimeSincePost AS TopAnswerAvgCommentTime,
    APM.HadOffTopicCloseReason AS HadOffTopicFlagOnTopAnswer,
    PH.EditCount AS UserTotalEdits, -- Re-purpose
    PH.CloseCount AS UserAvgPostScoreOverall, -- Re-purpose for Close Count
    RANK() OVER (ORDER BY P.Score DESC, P.ViewCount DESC) AS OverallUserRank, -- Rank posts
    'High-Impact Post' AS UserCategory,
    EXISTS (SELECT 1 FROM DuplicateLinkAnalysis DLA WHERE DLA.OriginalPostId = P.Id) AS HasDuplicateSourcePost,
    REPLACE(TRIM(SUBSTRING(P.Title, 1, 15)), ' ', '_') || '_' || UPPER(LEFT(COALESCE(P.ContentLicense, 'NONE'), 3)) AS UserSignature
FROM Posts AS P
INNER JOIN PostEditActivity AS PH ON P.Id = PH.PostId
LEFT JOIN AdvancedPostMetrics AS APM ON P.Id = APM.PostId
LEFT JOIN (SELECT TagName, TotalTagViewCount FROM TopTagsAndUsers WHERE TagRank <= 10) AS TTU_union ON P.Id IN (SELECT PTE_union.PostId FROM PostTagsExpanded PTE_union WHERE PTE_union.TagName = TTU_union.TagName)
WHERE P.PostTypeId = 1 -- Focus on questions
  AND P.Score > 50
  AND P.ViewCount > 1000
  AND PH.EditCount > 5
  AND (PH.CloseCount > 0 OR PH.RollbackCount > 0)
  AND P.CreationDate > CURRENT_DATE - INTERVAL '2 years'
  AND (P.Body LIKE '%performance%' OR P.Title LIKE '%benchmark%')
ORDER BY OverallUserRank ASC
LIMIT 250;
