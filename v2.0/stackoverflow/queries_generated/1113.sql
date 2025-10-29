-- {"query": "1113.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3590} 

WITH UserActivitySummary AS (
    -- This CTE aggregates various activities for each user, providing a comprehensive profile.
    -- It includes counts of owned posts, answers, comments, and badges.
    -- It also sums up positive and negative votes given by the user.
    -- COALESCE is used for safe handling of potentially NULL profile views.
    -- A calculation for hours since last access is included as a numeric value.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COALESCE(u.Views, 0) AS TotalProfileViews,
        u.UpVotes AS TotalUpVotesReceived, -- Total upvotes received on all posts/comments by the user
        u.DownVotes AS TotalDownVotesReceived, -- Total downvotes received on all posts/comments by the user
        COUNT(DISTINCT p_own.Id) AS TotalPostsOwned,
        COUNT(DISTINCT CASE WHEN p_own.PostTypeId = 2 THEN p_own.Id END) AS TotalAnswersOwned,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        COUNT(DISTINCT b.Id) AS TotalBadgesEarned,
        SUM(CASE WHEN v_given.VoteTypeId IN (2, 8) THEN 1 ELSE 0 END) AS TotalPositiveVotesGiven, -- VoteTypes: 2=UpMod, 8=BountyStart
        SUM(CASE WHEN v_given.VoteTypeId IN (3, 10, 12) THEN 1 ELSE 0 END) AS TotalNegativeVotesGiven, -- VoteTypes: 3=DownMod, 10=Deletion, 12=Spam
        MAX(u.LastAccessDate) AS LastUserAccessDate,
        (EXTRACT(EPOCH FROM NOW() - u.LastAccessDate) / 3600)::numeric(10, 2) AS HoursSinceLastAccess
    FROM
        Users u
    LEFT JOIN Posts p_own ON u.Id = p_own.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v_given ON u.Id = v_given.UserId -- Votes given *by* the user
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Views, u.UpVotes, u.DownVotes, u.LastAccessDate
),
PostEngagementMetrics AS (
    -- This CTE gathers core post-level engagement metrics and historical data.
    -- It includes counts for post edits and distinct editors from the PostHistory table,
    -- along with calculations for the post's age and the length of its body and title.
    -- COALESCE ensures that NULL counts (e.g., Score, ViewCount) default to 0.
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.AcceptedAnswerId,
        p.ParentId, -- Essential for linking answers to their parent questions
        p.CreationDate AS PostCreationDate,
        COALESCE(p.Score, 0) AS PostScore,
        COALESCE(p.ViewCount, 0) AS PostViewCount,
        p.OwnerUserId,
        p.LastEditorUserId,
        p.LastEditDate,
        p.LastActivityDate,
        p.Title AS PostTitle,
        p.Tags,
        COALESCE(p.AnswerCount, 0) AS PostAnswerCount,
        COALESCE(p.CommentCount, 0) AS PostCommentCount,
        COALESCE(p.FavoriteCount, 0) AS PostFavoriteCount,
        p.ClosedDate,
        (SELECT COUNT(ph.Id)
         FROM PostHistory ph
         WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4, 5, 6)) AS TotalEditHistoryCount, -- PostHistoryTypes: 4=Edit Title, 5=Edit Body, 6=Edit Tags
        (SELECT COUNT(DISTINCT ph.UserId)
         FROM PostHistory ph
         WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4, 5, 6) AND ph.UserId IS NOT NULL) AS DistinctEditorCount,
        (EXTRACT(EPOCH FROM NOW() - p.CreationDate) / (24 * 3600))::numeric(10, 2) AS DaysSinceCreation,
        LENGTH(p.Body) AS BodyLength,
        LENGTH(p.Title) AS TitleLength
    FROM
        Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
),
TagPerformance AS (
    -- This CTE analyzes performance metrics for individual tags, focusing on questions.
    -- It leverages `string_to_array` and `UNNEST` functions to parse tags embedded within post strings.
    -- Aggregations include total posts, average score, total views, and average body length for each tag.
    SELECT
        unnested_tag AS TagName,
        COUNT(p.Id) AS TotalPostsWithTag,
        AVG(p.Score) AS AvgScoreOfTaggedPosts,
        SUM(p.ViewCount) AS TotalViewsOfTaggedPosts,
        SUM(p.AnswerCount) AS TotalAnswersOfTaggedPosts,
        AVG(LENGTH(p.Body)) AS AvgBodyLengthForTag,
        MAX(p.CreationDate) AS LatestPostWithTag
    FROM
        Posts p,
        UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><')) AS unnested_tag
    WHERE
        p.Tags IS NOT NULL AND LENGTH(TRIM(p.Tags)) > 2 -- Ensures valid tags exist
        AND p.PostTypeId = 1 -- Tags are primarily associated with questions
    GROUP BY
        unnested_tag
),
CombinedPostMetrics AS (
    -- This CTE integrates data from the previous CTEs and applies a series of advanced window functions.
    -- It calculates various ranks (overall by post type, by tag score), moving averages over date ranges,
    -- running totals for views by owner, and uses LAG/NTH_VALUE for sequential and categorical analysis.
    -- A LATERAL JOIN is employed for efficient row-wise unnesting of tags.
    SELECT
        pem.PostId,
        pem.PostTitle,
        pem.PostTypeName,
        pem.PostTypeId,
        pem.PostCreationDate,
        pem.PostScore,
        pem.PostViewCount,
        pem.PostAnswerCount,
        pem.PostCommentCount,
        pem.PostFavoriteCount,
        pem.OwnerUserId,
        pem.ParentId, -- Included for correlated subqueries in the final SELECT
        uas.DisplayName AS OwnerDisplayName,
        uas.Reputation AS OwnerReputation,
        pem.TotalEditHistoryCount,
        pem.DistinctEditorCount,
        pem.DaysSinceCreation,
        pem.BodyLength,
        pem.TitleLength,
        unnested_tag.tag AS TagName,
        tp.AvgScoreOfTaggedPosts,
        tp.TotalPostsWithTag,
        tp.TotalViewsOfTaggedPosts,
        COALESCE(tp.AvgBodyLengthForTag, 0) AS TagAvgBodyLength,
        -- Window Functions:
        ROW_NUMBER() OVER (PARTITION BY pem.PostTypeId ORDER BY pem.PostScore DESC, pem.PostViewCount DESC) AS RankOverallByPostType,
        RANK() OVER (PARTITION BY unnested_tag.tag ORDER BY pem.PostScore DESC) AS RankByTagScore,
        AVG(pem.PostScore) OVER (PARTITION BY pem.PostTypeId ORDER BY pem.PostCreationDate RANGE BETWEEN INTERVAL '30' DAY PRECEDING AND CURRENT ROW) AS MovingAvgScore30Days,
        SUM(pem.PostViewCount) OVER (PARTITION BY pem.OwnerUserId ORDER BY pem.PostCreationDate) AS RunningTotalViewsByOwner,
        NTH_VALUE(pem.PostTitle, 1) OVER (PARTITION BY unnested_tag.tag ORDER BY pem.PostScore DESC) AS TopPostInTag,
        LAG(pem.PostScore, 1, 0) OVER (PARTITION BY pem.OwnerUserId ORDER BY pem.PostCreationDate) AS PreviousPostScoreByOwner
    FROM
        PostEngagementMetrics pem
    LEFT JOIN
        UserActivitySummary uas ON pem.OwnerUserId = uas.UserId
    LEFT JOIN LATERAL ( -- Lateral join to unnest tags efficiently per row
        SELECT tag
        FROM UNNEST(string_to_array(SUBSTRING(pem.Tags, 2, LENGTH(pem.Tags) - 2), '><')) AS tag
    ) AS unnested_tag ON pem.Tags IS NOT NULL AND LENGTH(TRIM(pem.Tags)) > 2
    LEFT JOIN
        TagPerformance tp ON unnested_tag.tag = tp.TagName
    WHERE
        pem.PostCreationDate >= (NOW() - INTERVAL '2 year') -- Filters for posts created in the last 2 years
        AND pem.PostTypeId IN (1, 2) -- Focuses on Questions (1) and Answers (2)
        AND pem.PostScore IS NOT NULL -- Ensures posts have a defined score
)
-- Main Query: This query combines two distinct analysis categories ("High Impact Questions" and "Underperforming Answers")
-- using a UNION ALL set operator. Each category applies a complex set of filters, including:
-- - Detailed predicates on post and user attributes.
-- - Correlated subqueries for dynamic filtering based on averages and related post data.
-- - String expressions (ILIKE) for text matching.
-- - NULL logic (COALESCE, IS NOT NULL, IS NULL) for robust data handling.
-- - Additional non-correlated subqueries in the SELECT list to fetch aggregated data.
SELECT
    'High Impact Questions' AS AnalysisCategory,
    cpm.PostId,
    cpm.PostTitle,
    cpm.PostTypeName,
    cpm.PostCreationDate,
    cpm.PostScore,
    cpm.PostViewCount,
    cpm.PostFavoriteCount,
    cpm.OwnerDisplayName,
    cpm.OwnerReputation,
    cpm.TagName,
    cpm.RankOverallByPostType,
    cpm.MovingAvgScore30Days,
    cpm.RunningTotalViewsByOwner,
    cpm.TopPostInTag,
    cpm.PreviousPostScoreByOwner,
    'Questions with significant view count, high score, and positive reputation from active users.' AS Insights,
    CASE
        WHEN cpm.PostFavoriteCount > 0 AND cpm.PostScore > cpm.MovingAvgScore30Days THEN 'Trending & Highly Rated'
        WHEN cpm.PostFavoriteCount > 0 THEN 'Frequently Favorited'
        ELSE 'High Score'
    END AS DetailedInsightType,
    (SELECT COUNT(c.Id) FROM Comments c WHERE c.PostId = cpm.PostId AND c.CreationDate > cpm.PostCreationDate + INTERVAL '1' WEEK) AS CommentsAfterFirstWeek -- Non-correlated subquery
FROM
    CombinedPostMetrics cpm
WHERE
    cpm.PostTypeId = 1 -- Filters for questions only
    AND cpm.RankOverallByPostType <= 500 -- Considers top 500 questions ranked by score and views within their type
    AND cpm.PostScore >= 50 -- Requires a minimum score of 50
    AND cpm.PostViewCount > (SELECT AVG(p_inner.ViewCount) * 2 FROM Posts p_inner WHERE p_inner.PostTypeId = cpm.PostTypeId) -- Correlated subquery: View count is more than double the average for its post type
    AND cpm.OwnerReputation > 1000 -- Requires the owner to have a reputation over 1000
    AND cpm.PostTitle ILIKE '%sql%' -- String expression: Post title must contain 'sql' (case-insensitive)
    AND cpm.TagName IS NOT NULL -- NULL logic: Ensures the post is tagged
    AND NOT EXISTS (
        SELECT 1 FROM PostLinks pl WHERE pl.PostId = cpm.PostId AND pl.LinkTypeId = 3 -- Correlated subquery: Excludes posts that are duplicates (LinkType 3 = Duplicate)
    )
    AND cpm.DaysSinceCreation BETWEEN 30 AND 365 -- Post created between 1 month and 1 year ago (active but not brand new)
    AND cpm.PostCommentCount > 0 -- Has at least one comment
UNION ALL
SELECT
    'Underperforming Answers' AS AnalysisCategory,
    cpm.PostId,
    cpm.PostTitle,
    cpm.PostTypeName,
    cpm.PostCreationDate,
    cpm.PostScore,
    cpm.PostViewCount,
    cpm.PostFavoriteCount,
    COALESCE(cpm.OwnerDisplayName, 'Community') AS OwnerDisplayName, -- NULL logic: Defaults to 'Community' if OwnerDisplayName is NULL (e.g., for deleted users)
    cpm.OwnerReputation,
    cpm.TagName,
    cpm.RankOverallByPostType,
    cpm.MovingAvgScore30Days,
    cpm.RunningTotalViewsByOwner,
    cpm.TopPostInTag,
    cpm.PreviousPostScoreByOwner,
    'Answers from active users with low scores relative to their parent question and lacking engagement.' AS Insights,
    CASE
        WHEN cpm.PostScore < cpm.PreviousPostScoreByOwner / 2 THEN 'Score significantly lower than previous post'
        WHEN cpm.PostScore < cpm.AvgScoreOfTaggedPosts THEN 'Below Tag Average Score'
        WHEN cpm.TotalEditHistoryCount < 2 THEN 'Infrequently Edited'
        ELSE 'General Underperformance'
    END AS DetailedInsightType,
    (SELECT COUNT(v.Id) FROM Votes v WHERE v.PostId = cpm.PostId AND v.VoteTypeId = 5) AS SavedCount -- Non-correlated subquery: Number of times saved/favorited (VoteType 5)
FROM
    CombinedPostMetrics cpm
WHERE
    cpm.PostTypeId = 2 -- Filters for answers only
    AND cpm.PostScore < (SELECT AVG(p_parent.Score) * 0.2 FROM Posts p_parent WHERE p_parent.Id = cpm.ParentId AND p_parent.PostTypeId = 1) -- Correlated subquery: Answer score is less than 20% of its parent question's average score
    AND cpm.PostCreationDate > (NOW() - INTERVAL '1 year') -- Answer created in the last year
    AND cpm.TotalEditHistoryCount < 3 -- Has been edited fewer than 3 times, suggesting less community input
    AND cpm.OwnerUserId IS NOT NULL -- Excludes answers from community wiki or deleted users
    AND cpm.RunningTotalViewsByOwner > 1000 -- Owner has a significant total view count, making the low answer score more notable
    AND cpm.TagName IS NOT NULL -- Ensures the answer's parent question has a tag
    AND (cpm.PostFavoriteCount IS NULL OR cpm.PostFavoriteCount = 0) -- NULL logic: Has received no favorites
    AND cpm.PostScore < cpm.PreviousPostScoreByOwner -- Score is lower than the owner's immediately previous post (using LAG)
    AND cpm.BodyLength > 100 -- Ensures it's not a trivial or very short answer
ORDER BY
    AnalysisCategory, PostScore ASC, PostViewCount DESC
LIMIT 1000; -- Limits the total output rows for practical benchmarking and result analysis
