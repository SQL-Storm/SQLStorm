-- {"query": "1231.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3084} 

WITH UserEngagement AS (
    -- CTE 1: Summarizes user activity, including posts, comments, votes, and badges.
    -- Uses LEFT JOIN to include users who might not have activity in all categories.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.Views AS UserProfileViews,
        COUNT(DISTINCT p.Id) AS TotalPostsCreated,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersProvided,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesGiven,
        MAX(b.Date) AS LastBadgeDate,
        COUNT(DISTINCT b.Id) AS TotalBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Views
),
PostHistoryTimeline AS (
    -- CTE 2: Analyzes post history for each post, using window functions to track revision changes.
    -- LAG/LEAD help in calculating time differences between consecutive history entries.
    SELECT
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate AS HistoryDate,
        ph.UserId AS HistoryUserId,
        LAG(ph.CreationDate, 1, ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PreviousHistoryDate,
        LEAD(ph.CreationDate, 1, ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS NextHistoryDate,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS RevisionRankAsc,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS RevisionRankDesc,
        ph.Text AS HistoryTextContent
    FROM PostHistory ph
    -- Filter relevant history types for edits, state changes, etc.
    WHERE ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 12, 13)
),
PostAggregatedMetrics AS (
    -- CTE 3: Aggregates various metrics for posts, including history, comments, and links.
    -- Incorporates complicated predicates, string expressions, and NULL logic.
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount AS OriginalCommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.LastActivityDate,
        LENGTH(p.Body) AS BodyLength,
        COUNT(DISTINCT pht.PostHistoryTypeId) AS DistinctHistoryTypes,
        COUNT(CASE WHEN pht.PostHistoryTypeId = 5 THEN 1 END) AS BodyEditCount, -- PostHistoryTypeId 5 is 'Edit Body'
        MAX(pht.HistoryDate) AS LastEditOrHistoryDate,
        -- Find the UserId of the user who made the very last edit/history entry
        MAX(pht.HistoryUserId) FILTER (WHERE pht.RevisionRankDesc = 1) AS LastEditorHistoryUserId,
        MIN(pht.HistoryDate) AS FirstHistoryDate,
        BOOL_OR(pht.PostHistoryTypeId = 10) AS WasClosed, -- PostHistoryTypeId 10 is 'Post Closed'
        BOOL_OR(pht.PostHistoryTypeId = 11) AS WasReopened, -- PostHistoryTypeId 11 is 'Post Reopened'
        BOOL_OR(pht.PostHistoryTypeId = 12) AS WasDeleted, -- PostHistoryTypeId 12 is 'Post Deleted'
        SUM(c.Score) AS TotalCommentScore,
        AVG(LENGTH(c.Text)) AS AvgCommentLength,
        MAX(c.Score) AS MaxCommentScore,
        COUNT(DISTINCT pl_linked.RelatedPostId) AS LinkedPostsCount,
        COUNT(DISTINCT pl_dup.RelatedPostId) AS DuplicatePostsCount,
        -- Complex string and NULL logic checks
        COALESCE(p.AcceptedAnswerId, -1) AS AcceptedAnswerIdOrDefault, -- Replaces NULL AcceptedAnswerId with -1
        POSITION('http' IN p.Body) > 0 OR POSITION('www.' IN p.Body) > 0 AS HasExternalLinkInBody,
        POSITION('<pre>' IN p.Body) > 0 OR POSITION('<code>' IN p.Body) > 0 AS ContainsCodeSnippet,
        CASE
            WHEN p.Title IS NULL THEN 'No Title'
            WHEN LENGTH(p.Title) < 20 THEN 'Short Title'
            WHEN LENGTH(p.Title) > 100 THEN 'Long Title'
            ELSE 'Normal Title'
        END AS TitleLengthCategory,
        NULLIF(p.AnswerCount, 0) AS AnswerCountOrNull -- Returns NULL if AnswerCount is 0, otherwise AnswerCount
    FROM Posts p
    LEFT JOIN PostHistoryTimeline pht ON p.Id = pht.PostId
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN PostLinks pl_linked ON p.Id = pl_linked.PostId AND pl_linked.LinkTypeId = 1 -- Linked posts
    LEFT JOIN PostLinks pl_dup ON p.Id = pl_dup.PostId AND pl_dup.LinkTypeId = 3 -- Duplicate posts
    GROUP BY
        p.Id, p.PostTypeId, p.CreationDate, p.OwnerUserId, p.Title, p.Tags, p.Score, p.ViewCount,
        p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ClosedDate, p.LastActivityDate, p.Body, p.AcceptedAnswerId
),
TagPerformance AS (
    -- CTE 4: Calculates performance metrics for individual tags.
    -- Uses unnest(string_to_array(...)) to split the 'Tags' string into individual tags.
    SELECT
        unnest(string_to_array(substring(p.Tags, 2, LENGTH(p.Tags) - 2), '><')) AS TagName, -- Parses '<tag1><tag2>' into 'tag1', 'tag2'
        COUNT(p.Id) AS PostsWithTag,
        SUM(p.Score) AS TagTotalScore,
        AVG(p.Score) AS TagAvgScore,
        AVG(p.ViewCount) AS TagAvgViewCount,
        AVG(p.AnswerCount) AS TagAvgAnswerCount,
        SUM(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS TagClosedPosts
    FROM Posts p
    WHERE p.Tags IS NOT NULL AND p.PostTypeId = 1 -- Only analyze tags from questions
    GROUP BY unnest(string_to_array(substring(p.Tags, 2, LENGTH(p.Tags) - 2), '><'))
)
-- Main Query: Joins the CTEs and applies further aggregations, window functions, and filters.
SELECT
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.UserCreationDate,
    pm.PostId,
    pm.PostTypeId,
    pm.Title,
    pm.PostScore,
    pm.ViewCount,
    pm.AnswerCount,
    pm.LastEditOrHistoryDate,
    pm.WasClosed,
    pm.ContainsCodeSnippet,
    pm.TitleLengthCategory,
    tp.TagName AS DominantTagName, -- The primary tag for the post, if multiple, this picks one arbitrarily after unnest.
    tp.TagAvgScore,
    -- Window functions for ranking and aggregation
    RANK() OVER (PARTITION BY pm.PostTypeId ORDER BY pm.PostScore DESC, pm.ViewCount DESC) AS PostRankByScoreViews,
    NTILE(10) OVER (ORDER BY ue.Reputation DESC, ue.TotalPostsCreated DESC) AS UserReputationTier,
    AVG(pm.PostScore) OVER (PARTITION BY pm.PostTypeId) AS AvgScoreForPostType,
    -- Correlated subquery: Fetches the text of the latest comment for the current post.
    (
        SELECT c_inner.Text
        FROM Comments c_inner
        WHERE c_inner.PostId = pm.PostId
        ORDER BY c_inner.CreationDate DESC
        LIMIT 1
    ) AS LatestCommentText,
    -- More complex calculations and expressions
    DATE_PART('day', NOW() - pm.LastActivityDate) AS DaysSinceLastActivity,
    COALESCE(pm.TotalCommentScore, 0) + COALESCE(pm.PostScore, 0) * 1.5 + COALESCE(pm.FavoriteCount, 0) * 2 AS EngagementIndex,
    -- Join with Users table to get last editor's display name, handling potential NULL
    COALESCE(leu.DisplayName, 'Community/Unknown') AS LastEditorDisplayName,
    -- Calculate ratio, handling division by zero explicitly
    CASE
        WHEN pm.ViewCount > 0 THEN CAST(pm.PostScore AS DECIMAL) / pm.ViewCount
        ELSE 0
    END AS ScorePerViewRatio,
    -- Correlated subquery: Counts how many questions have this post as their AcceptedAnswerId.
    (
        SELECT COUNT(DISTINCT q.Id) FROM Posts q WHERE q.AcceptedAnswerId = pm.PostId AND q.Id != pm.PostId
    ) AS IsAcceptedAnswerForQuestionsCount,
    -- Another complex ratio calculation with zero handling
    CASE
        WHEN pm.BodyLength > 0 AND pm.BodyEditCount > 0
        THEN CAST(pm.BodyEditCount AS DECIMAL) / pm.BodyLength
        ELSE 0
    END AS BodyEditDensity,
    pm.HasExternalLinkInBody,
    tp.TagTotalScore,
    -- Window function: Get the score of the previous post created by the same user
    LAG(pm.PostScore, 1, 0) OVER (PARTITION BY ue.UserId ORDER BY pm.PostCreationDate) AS PreviousPostScore,
    -- Further complex predicate example
    CASE
        WHEN pm.PostTypeId = 1 AND pm.AnswerCount > 0 AND pm.PostScore >= 10 THEN 'High_Quality_Question'
        WHEN pm.PostTypeId = 2 AND pm.AcceptedAnswerIdOrDefault != -1 AND pm.PostScore >= 5 THEN 'Accepted_Valuable_Answer'
        ELSE 'Other_Post_Type'
    END AS PostQualityCategory
FROM UserEngagement ue
JOIN PostAggregatedMetrics pm ON ue.UserId = pm.OwnerUserId
LEFT JOIN Users leu ON pm.LastEditorHistoryUserId = leu.Id -- To get display name of the last editor
LEFT JOIN LATERAL ( -- Lateral join to extract just one (the first) tag per post for joining with TagPerformance
    SELECT unnest(string_to_array(substring(p_inner.Tags, 2, LENGTH(p_inner.Tags) - 2), '><')) AS TagName
    FROM Posts p_inner
    WHERE p_inner.Id = pm.PostId AND p_inner.Tags IS NOT NULL AND p_inner.PostTypeId = 1
    LIMIT 1 -- Pick only one tag if multiple exist, for simplicity of joining to TagPerformance
) AS PostTags ON TRUE
LEFT JOIN TagPerformance tp ON PostTags.TagName = tp.TagName
WHERE
    ue.Reputation > 5000 -- Filter for highly reputed users
    AND pm.PostScore > 10 -- Filter for posts with significant positive score
    AND pm.PostTypeId IN (1, 2) -- Focus on Questions and Answers
    AND pm.BodyLength > 150 -- Ensure meaningful content length
    AND pm.DistinctHistoryTypes >= 3 -- Posts that have undergone several types of changes
    AND pm.WasClosed IS FALSE -- Exclude closed posts from the analysis
    AND pm.LastEditOrHistoryDate > ue.UserCreationDate + INTERVAL '90 days' -- Post was active significantly after user creation
    AND (
        pm.ContainsCodeSnippet = TRUE -- Posts containing code
        OR pm.HasExternalLinkInBody = TRUE -- Posts with external links
        OR pm.FavoriteCount > 5 -- Posts that are favorited frequently
        OR pm.TotalCommentScore > 10 -- Posts with high-scoring comments
    )
    AND pm.PostCreationDate BETWEEN '2020-01-01' AND '2023-12-31' -- Specific date range for posts
ORDER BY
    ue.Reputation DESC,
    pm.LastActivityDate DESC,
    PostRankByScoreViews ASC,
    pm.PostScore DESC
LIMIT 10000;
