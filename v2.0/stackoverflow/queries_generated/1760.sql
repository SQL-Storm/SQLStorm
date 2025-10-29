-- {"query": "1760.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3380} 

WITH UserEngagement AS (
    -- Summarizes user activity, calculates derived metrics, and filters for moderately active users.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.Views AS UserViews,
        U.UpVotes,
        U.DownVotes,
        U.Location,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COUNT(DISTINCT C.Id) AS TotalComments,
        MAX(B.Class) AS HighestBadgeClass, -- 1=Gold, 2=Silver, 3=Bronze
        MAX(U.LastAccessDate) AS LastUserActivity,
        -- Calculate ratio of upvotes to downvotes, handling division by zero with NULLIF
        CAST(U.UpVotes AS NUMERIC) / NULLIF(U.DownVotes, 0) AS UpDownVoteRatio,
        -- Check if user has badges related to specific tags (e.g., 'sql' or 'database')
        MAX(CASE WHEN B.Name ILIKE '%sql%' OR B.Name ILIKE '%database%' AND B.TagBased = TRUE THEN 1 ELSE 0 END) AS HasSqlOrDbTagBadge
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.Views, U.UpVotes, U.DownVotes, U.Location, U.LastAccessDate
    HAVING COUNT(DISTINCT P.Id) > 5 -- Filter for users with at least 5 posts
),
PostHistoricalContext AS (
    -- Gathers historical context for posts, including close/reopen events and latest editor info.
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.LastEditDate,
        P.ClosedDate,
        P.CommunityOwnedDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount AS PostCommentCount,
        P.Tags,
        -- Determine if a post has been closed, reopened, or deleted at any point
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS WasClosed,
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS WasReopened,
        MAX(CASE WHEN PH.PostHistoryTypeId = 12 THEN 1 ELSE 0 END) AS WasDeleted,
        -- Count distinct editors (excluding the original owner) for non-initial edits
        COUNT(DISTINCT PH.UserId) FILTER (WHERE PH.UserId IS NOT NULL AND PH.UserId != P.OwnerUserId AND PH.PostHistoryTypeId IN (4, 5, 6)) AS OtherEditorsCount,
        -- Get the most recent editor's ID if available
        MAX(CASE WHEN PH.CreationDate = P.LastEditDate THEN PH.UserId ELSE NULL END) AS LastEditorId,
        -- Extract the close reason if available (PostHistoryTypeId = 10)
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN COALESCE(PH.Comment, 'Unknown Reason') ELSE NULL END) AS CloseReason,
        -- Find the related post if it's a duplicate (LinkTypeId = 3)
        MAX(CASE WHEN PL.LinkTypeId = 3 THEN PL.RelatedPostId ELSE NULL END) AS DuplicateOfPostId
    FROM Posts AS P
    LEFT JOIN PostHistory AS PH ON P.Id = PH.PostId
    LEFT JOIN PostLinks AS PL ON P.Id = PL.PostId
    GROUP BY P.Id, P.PostTypeId, P.OwnerUserId, P.CreationDate, P.LastEditDate, P.ClosedDate, P.CommunityOwnedDate, P.Score, P.ViewCount, P.AnswerCount, P.CommentCount, P.Tags
),
CommentActivity AS (
    -- Aggregates comment scores and counts per post, calculating average length.
    SELECT
        PostId,
        SUM(Score) AS TotalCommentScore,
        COUNT(DISTINCT UserId) AS UniqueCommenters,
        AVG(LENGTH(Text)) AS AvgCommentLength,
        MAX(CreationDate) AS LastCommentDate,
        COUNT(*) AS CommentCountDetailed
    FROM Comments
    GROUP BY PostId
),
TagAnalysis AS (
    -- Analyzes tags for posts using string_to_array and UNNEST for precise tag matching.
    SELECT
        P.Id AS PostId,
        STRING_AGG(T.TagName, ', ') AS AllMatchedTags, -- Aggregates all matched tag names
        MAX(CASE WHEN T.TagName = 'sql' THEN 1 ELSE 0 END) AS HasSQLTag,
        MAX(CASE WHEN T.TagName = 'performance' THEN 1 ELSE 0 END) AS HasPerformanceTag,
        MAX(CASE WHEN T.TagName = 'optimization' THEN 1 ELSE 0 END) AS HasOptimizationTag
    FROM Posts AS P
    -- Use LATERAL JOIN with UNNEST to effectively split the tags string into rows
    LEFT JOIN LATERAL (
        SELECT tag
        FROM UNNEST(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><')) AS tag
    ) AS UnnestedTags (TagName) ON TRUE
    LEFT JOIN Tags AS T ON UnnestedTags.TagName = T.TagName
    WHERE P.Tags IS NOT NULL AND P.Tags != '' -- Exclude posts with no tags
    GROUP BY P.Id
)
-- Main Query Part 1: Combines data for high-reputation users who have posted recently closed technical questions.
SELECT
    'HighReputation_ClosedQuestions_TechFocused' AS AnalysisCategory,
    UE.DisplayName AS UserDisplayName,
    UE.Reputation AS UserReputation,
    UE.Location AS UserLocation,
    PHC.PostId,
    P.Title AS PostTitle,
    PHC.PostCreationDate,
    PHC.PostScore,
    PHC.ViewCount AS PostViewCount,
    PHC.AnswerCount,
    P.FavoriteCount,
    PHC.WasClosed,
    PHC.CloseReason,
    PHC.DuplicateOfPostId,
    CA.TotalCommentScore,
    CA.UniqueCommenters,
    CA.AvgCommentLength,
    TA.HasSQLTag,
    TA.HasPerformanceTag,
    TA.HasOptimizationTag,
    -- Correlated subquery: counts how many other posts by the same user were created within 7 days of this post.
    (
        SELECT COUNT(P2.Id)
        FROM Posts AS P2
        WHERE P2.OwnerUserId = UE.UserId
          AND P2.CreationDate BETWEEN PHC.PostCreationDate - INTERVAL '7 days' AND PHC.PostCreationDate + INTERVAL '7 days'
          AND P2.Id != PHC.PostId
    ) AS PeerPostsIn7Days,
    -- Window function: Ranks users by their reputation within their geographic location.
    RANK() OVER (PARTITION BY UE.Location ORDER BY UE.Reputation DESC, UE.UpDownVoteRatio DESC) AS RankInLocationByReputation,
    -- Window function: Calculates the moving average score of posts of the same type over the last year.
    AVG(P.Score) OVER (PARTITION BY P.PostTypeId ORDER BY P.CreationDate RANGE BETWEEN INTERVAL '365 days' PRECEDING AND CURRENT ROW) AS AvgScoreSamePostTypeLastYear,
    -- Complex calculation: An engagement factor derived from score, views, answers, and comments, normalized by post age.
    (PHC.PostScore * 1.5 + PHC.ViewCount * 0.01 + COALESCE(PHC.AnswerCount, 0) * 5 + COALESCE(CA.TotalCommentScore, 0) * 0.5) / NULLIF(DATE_PART('day', NOW() - PHC.PostCreationDate), 0) AS EngagementFactorPerDay,
    -- Complex conditional predicate to categorize post status based on historical and current attributes.
    CASE
        WHEN PHC.WasClosed = 1 AND PHC.CloseReason LIKE '%Duplicate%' THEN 'Closed_Duplicate'
        WHEN PHC.WasClosed = 1 AND PHC.CloseReason IS NOT NULL THEN 'Closed_Other'
        WHEN P.AcceptedAnswerId IS NOT NULL AND PHC.AnswerCount > 0 THEN 'Answered_Accepted'
        WHEN PHC.AnswerCount > 0 AND PHC.PostScore > 50 THEN 'Answered_Popular'
        ELSE 'Open_Active'
    END AS PostStatusCategory,
    -- String expression: Extracts a snippet of the post body, defaulting to a message if NULL.
    COALESCE(SUBSTRING(P.Body FROM 1 FOR 100), 'No Body Content') AS BodySnippet,
    -- NULL logic: Boolean flag indicating if a post has both an accepted answer and detailed comment activity.
    P.AcceptedAnswerId IS NOT NULL AND CA.CommentCountDetailed IS NOT NULL AS HasAcceptedAnswerAndComments
FROM UserEngagement AS UE
INNER JOIN PostHistoricalContext AS PHC ON UE.UserId = PHC.OwnerUserId
INNER JOIN Posts AS P ON PHC.PostId = P.Id
LEFT JOIN CommentActivity AS CA ON PHC.PostId = CA.PostId
LEFT JOIN TagAnalysis AS TA ON PHC.PostId = TA.PostId
WHERE
    UE.Reputation > 10000 -- Very high reputation users
    AND UE.LastUserActivity > NOW() - INTERVAL '6 months' -- Very recently active users
    AND PHC.PostTypeId = 1 -- Only analyze questions
    AND PHC.PostCreationDate > NOW() - INTERVAL '2 years' -- Recent questions
    AND PHC.WasClosed = 1 -- Specifically looking for closed questions
    AND (TA.HasSQLTag = 1 OR TA.HasPerformanceTag = 1) -- Questions tagged with 'sql' or 'performance'
    AND UE.TotalQuestions > 10 -- Users who have asked at least 10 questions
    AND (LOWER(UE.Location) LIKE '%europe%' OR LOWER(UE.Location) IS NULL) -- Users from Europe or unknown location
UNION ALL
-- Main Query Part 2: Combines data for moderately active users who have highly viewed/answered open questions, with different tag focus.
SELECT
    'ModerateReputation_PopularOpenQuestions_Optimized' AS AnalysisCategory,
    UE.DisplayName AS UserDisplayName,
    UE.Reputation AS UserReputation,
    UE.Location AS UserLocation,
    PHC.PostId,
    P.Title AS PostTitle,
    PHC.PostCreationDate,
    PHC.PostScore,
    PHC.ViewCount AS PostViewCount,
    PHC.AnswerCount,
    P.FavoriteCount,
    PHC.WasClosed,
    PHC.CloseReason,
    PHC.DuplicateOfPostId,
    CA.TotalCommentScore,
    CA.UniqueCommenters,
    CA.AvgCommentLength,
    TA.HasSQLTag,
    TA.HasPerformanceTag,
    TA.HasOptimizationTag,
    (
        SELECT COUNT(P2.Id)
        FROM Posts AS P2
        WHERE P2.OwnerUserId = UE.UserId
          AND P2.CreationDate BETWEEN PHC.PostCreationDate - INTERVAL '7 days' AND PHC.PostCreationDate + INTERVAL '7 days'
          AND P2.Id != PHC.PostId
    ) AS PeerPostsIn7Days,
    RANK() OVER (PARTITION BY UE.Location ORDER BY UE.Reputation DESC, UE.UpDownVoteRatio DESC) AS RankInLocationByReputation,
    AVG(P.Score) OVER (PARTITION BY P.PostTypeId ORDER BY P.CreationDate RANGE BETWEEN INTERVAL '365 days' PRECEDING AND CURRENT ROW) AS AvgScoreSamePostTypeLastYear,
    (PHC.PostScore * 1.5 + PHC.ViewCount * 0.01 + COALESCE(PHC.AnswerCount, 0) * 5 + COALESCE(CA.TotalCommentScore, 0) * 0.5) / NULLIF(DATE_PART('day', NOW() - PHC.PostCreationDate), 0) AS EngagementFactorPerDay,
    CASE
        WHEN PHC.WasClosed = 1 AND PHC.CloseReason LIKE '%Duplicate%' THEN 'Closed_Duplicate'
        WHEN PHC.WasClosed = 1 AND PHC.CloseReason IS NOT NULL THEN 'Closed_Other'
        WHEN P.AcceptedAnswerId IS NOT NULL AND PHC.AnswerCount > 0 THEN 'Answered_Accepted'
        WHEN PHC.AnswerCount > 0 AND PHC.PostScore > 50 THEN 'Answered_Popular'
        ELSE 'Open_Active'
    END AS PostStatusCategory,
    COALESCE(SUBSTRING(P.Body FROM 1 FOR 100), 'No Body Content') AS BodySnippet,
    P.AcceptedAnswerId IS NOT NULL AND CA.CommentCountDetailed IS NOT NULL AS HasAcceptedAnswerAndComments
FROM UserEngagement AS UE
INNER JOIN PostHistoricalContext AS PHC ON UE.UserId = PHC.OwnerUserId
INNER JOIN Posts AS P ON PHC.PostId = P.Id
LEFT JOIN CommentActivity AS CA ON PHC.PostId = CA.PostId
LEFT JOIN TagAnalysis AS TA ON PHC.PostId = TA.PostId
WHERE
    UE.Reputation BETWEEN 1000 AND 10000 -- Moderately high reputation users
    AND UE.LastUserActivity > NOW() - INTERVAL '1 year' -- Moderately recently active
    AND PHC.PostTypeId = 1 -- Only analyze questions
    AND PHC.PostCreationDate > NOW() - INTERVAL '3 years' -- Questions from the last 3 years
    AND PHC.WasClosed = 0 -- Specifically looking for open questions
    AND PHC.ViewCount > 5000 -- Highly viewed questions
    AND PHC.AnswerCount > 5 -- With multiple answers
    AND (TA.HasOptimizationTag = 1 OR TA.HasPerformanceTag = 1) -- Questions tagged with 'optimization' or 'performance'
    AND (LOWER(UE.Location) LIKE '%asia%' OR LOWER(UE.Location) IS NULL) -- Users from Asia or unknown location
ORDER BY UserReputation DESC, EngagementFactorPerDay DESC
LIMIT 2000;
