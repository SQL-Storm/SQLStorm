-- {"query": "1111.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2497} 
WITH UserPostSummary AS (
    SELECT
        OwnerUserId AS UserId,
        COUNT(Id) AS TotalPosts,
        COUNT(CASE WHEN PostTypeId = 1 THEN Id END) AS QuestionsPosted,
        COUNT(CASE WHEN PostTypeId = 2 THEN Id END) AS AnswersPosted,
        SUM(Score) AS TotalPostScore,
        SUM(CASE WHEN PostTypeId = 1 THEN ViewCount ELSE 0 END) AS TotalQuestionViews,
        MAX(CreationDate) AS LastPostDate,
        AVG(Score) FILTER (WHERE PostTypeId = 1) AS AvgQuestionScore,
        AVG(Score) FILTER (WHERE PostTypeId = 2) AS AvgAnswerScore
    FROM Posts
    WHERE OwnerUserId IS NOT NULL AND OwnerUserId != -1
    GROUP BY OwnerUserId
),
UserCommentSummary AS (
    SELECT
        UserId,
        COUNT(Id) AS CommentsMade
    FROM Comments
    WHERE UserId IS NOT NULL
    GROUP BY UserId
),
UserEngagement AS (
    -- CTE 1: Summarize user engagement metrics, handling potential NULLs from LEFT JOINs
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate,
        U.LastAccessDate,
        U.Views AS UserViews,
        U.UpVotes AS UserUpVotes,
        U.DownVotes AS UserDownVotes,
        COALESCE(UPS.TotalPosts, 0) AS TotalPosts,
        COALESCE(UPS.QuestionsPosted, 0) AS QuestionsPosted,
        COALESCE(UPS.AnswersPosted, 0) AS AnswersPosted,
        COALESCE(UCS.CommentsMade, 0) AS CommentsMade,
        COALESCE(UPS.TotalPostScore, 0) AS TotalPostScore,
        COALESCE(UPS.TotalQuestionViews, 0) AS TotalQuestionViews,
        UPS.LastPostDate,
        UPS.AvgQuestionScore,
        UPS.AvgAnswerScore
    FROM Users U
    LEFT JOIN UserPostSummary UPS ON U.Id = UPS.UserId
    LEFT JOIN UserCommentSummary UCS ON U.Id = UCS.UserId
),
PostDetailsWithTags AS (
    -- CTE 2: Extract tags, calculate some post metrics, and handle potential NULLs for titles/body
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        PT.Name AS PostTypeName,
        P.OwnerUserId,
        P.LastEditorUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount AS PostViewCount,
        P.AnswerCount,
        P.CommentCount AS PostCommentCount,
        P.FavoriteCount AS PostFavoriteCount,
        P.AcceptedAnswerId,
        P.ClosedDate,
        P.CommunityOwnedDate,
        COALESCE(P.Title, SUBSTRING(P.Body, 1, 100) || '...') AS PostTitleOrBodyExcerpt, -- String expression and NULL logic
        -- Split tags into an array and count them
        CASE
            WHEN P.Tags IS NOT NULL AND LENGTH(TRIM(P.Tags)) > 2
            THEN ARRAY_LENGTH(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><'), 1)
            ELSE 0
        END AS TagCount,
        string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><') AS PostTagsArray, -- String expression
        -- Calculate time difference in hours between last activity and creation
        EXTRACT(EPOCH FROM (P.LastActivityDate - P.CreationDate)) / 3600 AS HoursToLastActivity,
        -- Boolean check if post has an accepted answer (only relevant for questions)
        CASE WHEN P.PostTypeId = 1 AND P.AcceptedAnswerId IS NOT NULL THEN TRUE ELSE FALSE END AS HasAcceptedAnswer
    FROM Posts P
    INNER JOIN PostTypes PT ON P.PostTypeId = PT.Id
    WHERE P.PostTypeId IN (1, 2) -- Focus on Questions (1) and Answers (2) for deeper analysis
),
PostHistoryAggregates AS (
    -- CTE 3: Aggregate post history for each post, including a correlated subquery for the latest editor
    SELECT
        PH.PostId,
        COUNT(PH.Id) AS TotalHistoryEntries,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount, -- Edit Title, Body, Tags
        SUM(CASE WHEN PH.PostHistoryTypeId IN (10, 11) THEN 1 ELSE 0 END) AS CloseReopenCount, -- Post Closed, Post Reopened
        MAX(PH.CreationDate) AS LastHistoryDate,
        -- Correlated subquery to find the UserId of the latest editor based on post history types
        (SELECT PH2.UserId
         FROM PostHistory PH2
         WHERE PH2.PostId = PH.PostId
           AND PH2.PostHistoryTypeId IN (4, 5, 6) -- Look for edit types
         ORDER BY PH2.CreationDate DESC
         LIMIT 1) AS LastEditorIdByHistory
    FROM PostHistory PH
    GROUP BY PH.PostId
),
RankedUserMetrics AS (
    -- CTE 4: Rank users based on various engagement metrics using window functions
    SELECT
        UE.UserId,
        UE.DisplayName,
        UE.Reputation,
        UE.QuestionsPosted,
        UE.AnswersPosted,
        UE.TotalPosts,
        UE.CommentsMade,
        UE.TotalPostScore,
        UE.TotalQuestionViews,
        UE.AvgQuestionScore,
        UE.AvgAnswerScore,
        -- Rank users by overall reputation and last access date
        RANK() OVER (ORDER BY UE.Reputation DESC, UE.LastAccessDate DESC) AS OverallReputationRank,
        -- Rank users by questions posted within their creation year partition
        ROW_NUMBER() OVER (PARTITION BY EXTRACT(YEAR FROM UE.CreationDate) ORDER BY UE.QuestionsPosted DESC) AS QuestionsRankThisYear,
        -- Average total post score for users who joined in the same month
        AVG(UE.TotalPostScore) OVER (PARTITION BY EXTRACT(MONTH FROM UE.CreationDate)) AS AvgMonthlyTotalScoreForJoiners
    FROM UserEngagement UE
    WHERE UE.Reputation > 0 -- Filter out users with zero reputation for more meaningful rankings
)
-- Main query: Combines all CTEs to generate a comprehensive report on user-post interactions
SELECT
    RUM.UserId,
    RUM.DisplayName AS UserDisplayName,
    RUM.Reputation,
    RUM.OverallReputationRank,
    RUM.QuestionsRankThisYear,
    RUM.AvgMonthlyTotalScoreForJoiners,
    P.PostId,
    P.PostTypeName,
    P.PostTitleOrBodyExcerpt,
    P.PostScore,
    P.PostViewCount,
    P.PostFavoriteCount,
    P.HasAcceptedAnswer,
    P.TagCount,
    P.HoursToLastActivity,
    PHA.TotalHistoryEntries,
    PHA.EditCount AS PostEditCount,
    PHA.CloseReopenCount,
    COALESCE(U_Owner.DisplayName, 'Community User') AS OwnerDisplayName, -- NULL logic, OwnerUserId can be -1 or actual NULL
    -- COALESCE to prioritize LastEditorUserId, then history, then default
    COALESCE(U_PostEditor.DisplayName, U_HistoryEditor.DisplayName, 'System/Unknown Editor') AS LastKnownEditorDisplayName,
    -- Complicated calculation: engagement ratio, handling potential division by zero
    CASE
        WHEN P.PostViewCount > 0 THEN CAST(P.PostFavoriteCount + P.PostCommentCount + COALESCE(P.AnswerCount, 0) * 2 AS NUMERIC) / P.PostViewCount
        ELSE 0
    END AS EngagementRatio,
    -- String operations/array functions to check for intersection with specific tags
    (P.PostTagsArray && ARRAY['sql', 'performance', 'database', 'optimization']) AS ContainsRelevantTags,
    -- Conditional logic to determine a post's activity status
    CASE
        WHEN P.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN P.CommunityOwnedDate IS NOT NULL THEN 'Community-Owned'
        WHEN P.HasAcceptedAnswer THEN 'Answered & Accepted'
        WHEN P.PostCommentCount > 5 OR P.PostFavoriteCount > 10 THEN 'Highly Engaged'
        WHEN P.PostViewCount > 1000 AND P.PostScore > 5 THEN 'Popular'
        ELSE 'Active'
    END AS PostActivityStatus,
    -- Correlated subquery to get the score of the accepted answer, if available
    (SELECT COALESCE(A.Score, 0)
     FROM Posts A
     WHERE A.Id = P.AcceptedAnswerId AND P.HasAcceptedAnswer) AS AcceptedAnswerScore,
    -- Calculate absolute difference in reputation between owner and last known editor
    ABS(COALESCE(U_Owner.Reputation, 0) - COALESCE(U_PostEditor.Reputation, COALESCE(U_HistoryEditor.Reputation, 0))) AS OwnerEditorReputationDiff
FROM RankedUserMetrics RUM
INNER JOIN PostDetailsWithTags P ON RUM.UserId = P.OwnerUserId
LEFT JOIN PostHistoryAggregates PHA ON P.PostId = PHA.PostId
LEFT JOIN Users U_Owner ON P.OwnerUserId = U_Owner.Id
LEFT JOIN Users U_PostEditor ON P.LastEditorUserId = U_PostEditor.Id
LEFT JOIN Users U_HistoryEditor ON PHA.LastEditorIdByHistory = U_HistoryEditor.Id -- Join for editor from history CTE
WHERE
    RUM.Reputation > 5000 -- Filter for highly reputed users
    AND P.PostCreationDate >= '2021-01-01' -- Focus on recent posts for current trends
    AND P.PostScore >= 0 -- Exclude severely downvoted or deleted posts (score < 0 for some post types)
    AND P.PostTypeName = 'Question' -- Analyze only questions for this specific benchmark path
    AND (
        (P.PostViewCount > 1000 AND P.PostScore > 5 AND P.HasAcceptedAnswer) -- High visibility, good score, and resolved
        OR
        (P.PostCommentCount > 10 AND P.PostFavoriteCount > 15) -- Very high engagement
        OR
        (P.TagCount >= 3 AND P.PostTagsArray && ARRAY['api', 'json', 'data-structures']) -- Complex questions with specific tags
    ) -- Complex predicate for filtering relevant posts
ORDER BY
    RUM.Reputation DESC,
    EngagementRatio DESC,
    P.PostCreationDate DESC,
    PostActivityStatus
LIMIT 2500;