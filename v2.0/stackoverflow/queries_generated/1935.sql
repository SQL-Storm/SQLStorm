-- {"query": "1935.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2393} 

WITH TaggedPosts AS (
    -- CTE 1: Extracts and normalizes tags from Posts, filtering for specific post types (Questions and Answers)
    -- This CTE handles the complex string manipulation for tags and associates them with core post metadata.
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount,
        COALESCE(p.FavoriteCount, 0) AS FavoriteCount, -- NULL logic: Default FavoriteCount to 0 if NULL
        COALESCE(p.LastEditDate, p.CreationDate) AS EffectiveLastActivityDate, -- NULL logic: Use CreationDate if LastEditDate is NULL
        LOWER(UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><'))) AS TagName, -- String expressions: SUBSTRING, LENGTH, string_to_array, UNNEST, LOWER
        p.ParentId -- Useful for linking answers back to questions
    FROM
        Posts p
    WHERE
        p.PostTypeId IN (1, 2) -- Complicated predicate: Focus on Questions and Answers
        AND p.OwnerUserId IS NOT NULL -- NULL logic: Exclude posts without a clear owner
        AND p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2 -- String expressions: Ensure valid tag strings exist
),
ActiveUsersWithMetrics AS (
    -- CTE 2: Aggregates key activity metrics for users, focusing on those with a decent reputation and recent engagement.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.Views AS UserViews,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions, -- Conditional aggregation
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,   -- Conditional aggregation
        SUM(p.Score) AS TotalPostScore,
        AVG(CAST(p.Score AS NUMERIC)) AS AvgPostScore,
        -- Correlated subquery: Counts how many of this user's answers have been accepted by any question.
        (
            SELECT COUNT(q.Id)
            FROM Posts q
            WHERE q.AcceptedAnswerId IN (SELECT p_ans.Id FROM Posts p_ans WHERE p_ans.OwnerUserId = u.Id AND p_ans.PostTypeId = 2)
        ) AS AcceptedAnswersProvided,
        MAX(p.LastActivityDate) AS LastPostActivity
    FROM
        Users u
    JOIN
        Posts p ON u.Id = p.OwnerUserId
    WHERE
        u.Reputation >= 1000 -- Complicated predicate: Filter for reputable users
        AND u.LastAccessDate >= CURRENT_TIMESTAMP - INTERVAL '1 year' -- Complicated predicate: Active in the last year
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Views, u.UpVotes, u.DownVotes
    HAVING
        COUNT(DISTINCT p.Id) >= 5 -- Complicated predicate: Filter for users with a minimum number of posts
),
PostHistoryAggregates AS (
    -- CTE 3: Summarizes post history, including total edits and the details of the most recent close reason.
    SELECT
        ph.PostId,
        COUNT(ph.Id) AS TotalHistoryEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) THEN 1 ELSE 0 END) AS TotalEdits, -- Conditional aggregation: Count various edit types
        MAX(ph.CreationDate) AS LastHistoryDate,
        -- Correlated subquery: Retrieves the comment of the most recent 'Post Closed' event for a post.
        (
            SELECT Comment
            FROM PostHistory ph_inner
            WHERE ph_inner.PostId = ph.PostId
              AND ph_inner.PostHistoryTypeId = 10 -- Post Closed type
            ORDER BY ph_inner.CreationDate DESC
            LIMIT 1
        ) AS LastCloseReasonComment,
        -- Correlated subquery: Gets the PostHistoryTypeId of the very last event for the post.
        (
            SELECT ph_inner.PostHistoryTypeId
            FROM PostHistory ph_inner
            WHERE ph_inner.PostId = ph.PostId
            ORDER BY ph_inner.CreationDate DESC
            LIMIT 1
        ) AS LastHistoryEventTypeId
    FROM
        PostHistory ph
    GROUP BY
        ph.PostId
)
-- Main Query: Identifies highly engaged users contributing to specific tags, analyzing their post quality,
-- editing trends, badge achievements, and participation in linked/duplicated content.
SELECT
    au.UserId,
    au.DisplayName,
    au.Reputation,
    au.TotalPosts,
    au.TotalQuestions,
    au.TotalAnswers,
    au.AcceptedAnswersProvided,
    au.TotalPostScore,
    au.AvgPostScore,
    tp.TagName,
    COUNT(tp.PostId) AS PostsInThisTag,
    AVG(CAST(tp.PostScore AS NUMERIC)) AS AvgTagPostScore,
    SUM(tp.ViewCount) AS TotalTagViews,
    SUM(tp.FavoriteCount) AS TotalTagFavorites,
    SUM(ph.TotalEdits) AS TotalEditsOnTagPosts,
    -- Window function: Ranks users within each tag by a calculated contribution score.
    RANK() OVER (PARTITION BY tp.TagName ORDER BY (au.Reputation * 0.1 + au.AcceptedAnswersProvided * 50 + au.AvgPostScore * 10) DESC) AS RankInTagByContribution,
    -- Complicated calculation: A weighted sum to determine overall contribution.
    (au.Reputation * 0.1 + au.AcceptedAnswersProvided * 50 + au.AvgPostScore * 10) AS OverallContributionScore,
    -- Conditional aggregation & string expression: Calculates average body length for questions specific to this user and tag.
    AVG(CASE WHEN p_base.PostTypeId = 1 THEN LENGTH(p_base.Body) ELSE NULL END) AS AvgQuestionBodyLength,
    -- Complicated predicate & string expression: Checks if the user has a question related to 'SQL' within the 'sql' tag.
    MAX(CASE WHEN p_base.PostTypeId = 1 AND p_base.Title ILIKE '%SQL%' AND tp.TagName = 'sql' THEN 1 ELSE 0 END) AS HasSpecificSqlQuestion,
    -- NULL logic: Indicates if any of the user's posts within this tag have been closed.
    MAX(CASE WHEN ph.LastHistoryEventTypeId = 10 THEN 'Yes' ELSE 'No' END) AS HasClosedPostsInTag,
    -- Conditional aggregation: Counts badges by class (Gold, Silver, Bronze).
    COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadgesCount,
    COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadgesCount,
    COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadgesCount,
    -- Correlated subquery & string expression: Counts gold badges whose name is related to the current tag.
    (
        SELECT COUNT(b2.Id)
        FROM Badges b2
        WHERE b2.UserId = au.UserId
          AND b2.Class = 1 -- Gold badge
          AND b2.Name ILIKE '%' || tp.TagName || '%' -- String expression: Badge name containing tag name
    ) AS SpecificTagGoldBadgesCount,
    -- NULL logic & string expression: Displays the most recent close reason comment, defaulting to 'N/A'.
    COALESCE(ph.LastCloseReasonComment, 'N/A') AS MostRecentCloseReason,
    -- Complicated calculation & NULL logic: Ratio of accepted answers to total answers provided by the user, handling division by zero.
    COALESCE(CAST(au.AcceptedAnswersProvided AS NUMERIC) / NULLIF(au.TotalAnswers, 0), 0) AS UserOverallAcceptedAnswerRatio,
    -- Outer join logic: Checks if any of the user's questions in this tag are marked as duplicates.
    MAX(CASE WHEN pl.LinkTypeId = 3 AND tp.PostTypeId = 1 THEN 1 ELSE 0 END) AS HasDuplicateQuestionLinked
FROM
    ActiveUsersWithMetrics au
JOIN
    TaggedPosts tp ON au.UserId = tp.OwnerUserId
JOIN
    Posts p_base ON tp.PostId = p_base.Id -- Joins back to original Posts table for full access to Body, Title etc.
LEFT JOIN
    PostHistoryAggregates ph ON tp.PostId = ph.PostId -- Outer join for post history details
LEFT JOIN
    Badges b ON au.UserId = b.UserId -- Outer join for user badges
LEFT JOIN
    PostLinks pl ON tp.PostId = pl.PostId AND tp.PostTypeId = 1 -- Outer join for post links, focusing on question duplicates
WHERE
    tp.PostCreationDate >= CURRENT_TIMESTAMP - INTERVAL '2 years' -- Complicated predicate: Posts within a recent time frame
    AND tp.PostScore > 0 -- Complicated predicate: Only positive-scored posts
    AND LENGTH(p_base.Body) BETWEEN 50 AND 5000 -- Complicated predicate: Filter for reasonable body length
    AND p_base.CommentCount > 0 -- Complicated predicate: Ensure posts have at least one comment
GROUP BY
    au.UserId, au.DisplayName, au.Reputation, au.TotalPosts, au.TotalQuestions, au.TotalAnswers,
    au.AcceptedAnswersProvided, au.TotalPostScore, au.AvgPostScore, tp.TagName, ph.LastCloseReasonComment
HAVING
    COUNT(tp.PostId) >= 3 -- Complicated predicate: User must have at least 3 posts in the specific tag
    AND SUM(ph.TotalEdits) > 0 -- Complicated predicate: User's posts in this tag must have been edited at least once
ORDER BY
    OverallContributionScore DESC, au.Reputation DESC, PostsInThisTag DESC, tp.TagName ASC;
