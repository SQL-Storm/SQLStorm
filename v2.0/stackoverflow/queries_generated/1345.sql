-- {"query": "1345.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 4528} 

WITH UserActivitySummary AS (
    -- CTE 1: Aggregates user-level statistics like total posts, scores, badges, and account age.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScore,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        COUNT(b.Id) AS TotalBadges,
        MAX(p.CreationDate) AS LastPostDate,
        EXTRACT(EPOCH FROM (NOW() - u.CreationDate)) / (60 * 60 * 24) AS AccountAgeDays -- PostgreSQL specific age in days
    FROM
        Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostEditAnalysis AS (
    -- CTE 2: Analyzes post revision history, counting edits, distinct editors, and closure/reopening events.
    SELECT
        ph.PostId,
        COUNT(ph.Id) AS TotalRevisions,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 END) AS ContentEdits, -- Edit Title, Edit Body, Edit Tags
        MAX(ph.CreationDate) AS LastEditDate,
        MIN(ph.CreationDate) AS FirstEditDate,
        -- Correlated subquery to count distinct users who edited this post
        (SELECT COUNT(DISTINCT UserId) FROM PostHistory WHERE PostId = ph.PostId AND UserId IS NOT NULL) AS DistinctEditors,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS ClosureEvents, -- Post Closed
        SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenEvents -- Post Reopened
    FROM
        PostHistory ph
    GROUP BY
        ph.PostId
),
PostTaggingContext AS (
    -- CTE 3: Extracts the primary tag for each post and counts linked/duplicate posts.
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Tags,
        -- String expression: Extract the first tag from the '<tag1><tag2>' string
        CASE
            WHEN p.Tags IS NOT NULL AND LENGTH(TRIM(p.Tags)) > 2
            THEN (string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><'))[1]
            ELSE NULL
        END AS PrimaryTag,
        -- Correlated subquery: Count duplicate links for the post
        (SELECT COUNT(pl.RelatedPostId) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS DuplicateLinkCount,
        -- Correlated subquery: Count linked posts for the post
        (SELECT COUNT(pl.RelatedPostId) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 1) AS LinkedPostCount
    FROM
        Posts p
    WHERE p.PostTypeId IN (1, 2) -- Only questions and answers relevant for tags and links
)
-- Main Query: Combines data from CTEs and applies complex filtering, window functions, and set operators.
SELECT
    'HighImpactQuestion' AS RecordType, -- Categorical identifier for UNION ALL
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    p.Id AS PostId,
    p.Title,
    p.CreationDate AS PostCreationDate,
    p.Score AS PostScore,
    p.ViewCount AS PostViewCount,
    pe.TotalRevisions,
    pe.ContentEdits,
    pe.DistinctEditors,
    pe.ClosureEvents,
    pe.ReopenEvents,
    ptc.PrimaryTag,
    ptc.DuplicateLinkCount,
    ptc.LinkedPostCount,
    COALESCE(p.AcceptedAnswerId IS NOT NULL, FALSE) AS HasAcceptedAnswer, -- NULL logic: check if an accepted answer exists
    b_tag.Id IS NOT NULL AS HasPrimaryTagGoldBadge, -- Check for a gold badge for the primary tag
    -- Correlated subquery: Average score of user's *previous* posts of the same type in the last 60 days
    (
        SELECT AVG(pp.Score)
        FROM Posts pp
        WHERE pp.OwnerUserId = p.OwnerUserId
          AND pp.PostTypeId = p.PostTypeId
          AND pp.CreationDate BETWEEN (p.CreationDate - INTERVAL '60 days') AND p.CreationDate
          AND pp.Id != p.Id -- Exclude current post
    ) AS AvgUserScoreLast60DaysBeforePost,
    -- Complex expression: Categorize post impact based on views and score
    CASE
        WHEN p.ViewCount > 50000 AND p.Score > 200 THEN 'Mega Impact'
        WHEN p.ViewCount > 10000 AND p.Score > 50 THEN 'High Impact'
        WHEN p.ViewCount > 1000 AND p.Score > 10 THEN 'Medium Impact'
        ELSE 'Low Impact'
    END AS PostImpactCategory,
    -- Complex expression: Determine post status based on closure and community ownership
    CASE
        WHEN p.ClosedDate IS NOT NULL AND pe.ClosureEvents > 0 AND pe.ReopenEvents = 0 THEN 'Permanently Closed'
        WHEN p.ClosedDate IS NOT NULL AND pe.ReopenEvents > 0 THEN 'Closed & Reopened'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Active'
    END AS PostStatusFlag,
    -- Window function: Rolling average score of user's posts over a 90-day window (by row count)
    AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN 90 PRECEDING AND CURRENT ROW) AS UserRollingAvgScore90Days,
    -- Window function: Total favorite count for all posts by the user
    SUM(p.FavoriteCount) OVER (PARTITION BY p.OwnerUserId) AS TotalFavoritesByUser,
    -- Window function: Creation date of the user's previous post
    LAG(p.CreationDate, 1, p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostCreationDate,
    -- Calculation: Days since previous post using LAG
    EXTRACT(EPOCH FROM (p.CreationDate - LAG(p.CreationDate, 1, p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate))) / (60 * 60 * 24) AS DaysSincePreviousPost,
    -- Window function: Count of comments for the current post
    COUNT(cmt.Id) OVER (PARTITION BY p.Id) AS PostCommentCountWindow,
    -- String expression: Check for common code block markers in the post body
    CASE WHEN p.Body LIKE '%<pre><code>%' OR p.Body LIKE '%`%`%' THEN TRUE ELSE FALSE END AS HasCodeBlock,
    -- NULL logic: Check if the post was edited by a user different from the owner
    NULLIF(p.LastEditorUserId, p.OwnerUserId) IS NOT NULL AS EditedByOtherUser,
    -- Check if the primary tag has an associated wiki post
    t_wiki.Id IS NOT NULL AS PrimaryTagHasWikiPost,
    -- Complex string expression: Count how many tags are SQL-related using string_to_array and ILIKE
    COALESCE(ARRAY_LENGTH(ARRAY(SELECT unnest FROM unnest(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><')) WHERE unnest ILIKE '%sql%'), 1), 0) AS SQLRelatedTagCount,
    -- Correlated subquery for comment score analysis: sum of upvoted comments after 1 hour from post creation
    (
        SELECT SUM(c_inner.Score)
        FROM Comments c_inner
        WHERE c_inner.PostId = p.Id
          AND c_inner.UserId IS NOT NULL
          AND c_inner.CreationDate > p.CreationDate + INTERVAL '1 hour'
          AND c_inner.Score > 0
    ) AS PostCommentUpvoteSum
FROM
    UserActivitySummary uas
INNER JOIN Posts p ON uas.UserId = p.OwnerUserId
LEFT JOIN PostEditAnalysis pe ON p.Id = pe.PostId
LEFT JOIN PostTaggingContext ptc ON p.Id = ptc.PostId
LEFT JOIN Badges b_tag ON uas.UserId = b_tag.UserId
    AND ptc.PrimaryTag IS NOT NULL
    AND b_tag.Name = ptc.PrimaryTag
    AND b_tag.Class = 1 -- Gold badge for primary tag
LEFT JOIN Comments cmt ON p.Id = cmt.PostId
LEFT JOIN Tags t_wiki ON ptc.PrimaryTag = t_wiki.TagName AND t_wiki.WikiPostId IS NOT NULL
WHERE
    p.PostTypeId = 1 -- Focus on Questions
    AND uas.Reputation > 5000 -- Filter for high-reputation users
    AND p.CreationDate >= '2021-01-01' -- Recent activity
    AND p.ViewCount > 1000
    AND p.Score > 10
    AND EXISTS (
        -- Correlated subquery: Post is a duplicate (LinkTypeId = 3)
        SELECT 1 FROM PostLinks pl_duplicate WHERE pl_duplicate.PostId = p.Id AND pl_duplicate.LinkTypeId = 3
    )
    AND (p.Title ILIKE '%performance%' OR p.Tags ILIKE '%<optimization>%') -- String expressions: keywords in title or tags
    AND pe.ContentEdits > 2 -- Question has been edited multiple times
    AND pe.DistinctEditors > 1 -- By multiple users
    AND COALESCE(p.FavoriteCount, 0) > 5 -- Highly favorited
    AND EXISTS (
        -- Correlated subquery: Has at least one highly upvoted answer from a very high-rep user
        SELECT 1
        FROM Users u_answerer
        INNER JOIN Posts a ON u_answerer.Id = a.OwnerUserId
        WHERE a.ParentId = p.Id AND a.PostTypeId = 2 AND u_answerer.Reputation > 10000 AND a.Score > 20
    )
GROUP BY
    uas.UserId, uas.DisplayName, uas.Reputation, uas.AccountAgeDays, uas.TotalPosts, uas.TotalQuestions, uas.TotalAnswers,
    uas.TotalPostScore, uas.TotalBadges, p.Id, p.PostTypeId, p.Title, p.CreationDate, p.Score, p.ViewCount,
    p.AnswerCount, p.CommentCount, p.FavoriteCount, pe.TotalRevisions, pe.ContentEdits, pe.DistinctEditors,
    pe.ClosureEvents, pe.ReopenEvents, ptc.PrimaryTag, ptc.DuplicateLinkCount, ptc.LinkedPostCount, p.AcceptedAnswerId,
    b_tag.Id, p.Body, p.ClosedDate, p.CommunityOwnedDate, p.LastEditorUserId, p.OwnerUserId, t_wiki.Id
HAVING
    COUNT(DISTINCT cmt.Id) > 3 -- Aggregate condition: At least 3 distinct comments
    AND AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN 90 PRECEDING AND CURRENT ROW) > 15 -- Window function in HAVING
    AND SUM(p.FavoriteCount) OVER (PARTITION BY p.OwnerUserId) > 20 -- Another window function in HAVING

UNION ALL -- Set operator: Combine results for questions and answers

-- Second part of the UNION: Recent, highly-scored answers by users with many badges
SELECT
    'TopAnswererInsights' AS RecordType, -- Categorical identifier for UNION ALL
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    p.Id AS PostId,
    p.Title, -- Title is NULL for answers, but included for consistent schema
    p.CreationDate AS PostCreationDate,
    p.Score AS PostScore,
    p.ViewCount AS PostViewCount, -- ViewCount is NULL for answers, but included for consistent schema
    pe.TotalRevisions,
    pe.ContentEdits,
    pe.DistinctEditors,
    pe.ClosureEvents,
    pe.ReopenEvents,
    ptc.PrimaryTag, -- PrimaryTag is NULL for answers, but included for consistent schema
    ptc.DuplicateLinkCount, -- DuplicateLinkCount is NULL for answers, but included for consistent schema
    ptc.LinkedPostCount,    -- LinkedPostCount is NULL for answers, but included for consistent schema
    COALESCE(p.AcceptedAnswerId IS NOT NULL, FALSE) AS HasAcceptedAnswer, -- Always FALSE for answers, but included
    b_tag.Id IS NOT NULL AS HasPrimaryTagGoldBadge,
    -- Correlated subquery: Average score of user's *previous* posts of the same type in the last 60 days
    (
        SELECT AVG(pp.Score)
        FROM Posts pp
        WHERE pp.OwnerUserId = p.OwnerUserId
          AND pp.PostTypeId = p.PostTypeId
          AND pp.CreationDate BETWEEN (p.CreationDate - INTERVAL '60 days') AND p.CreationDate
          AND pp.Id != p.Id
    ) AS AvgUserScoreLast60DaysBeforePost,
    -- Complex expression: Categorize answer impact based on score
    CASE
        WHEN p.Score > 50 THEN 'Highly Valued Answer'
        WHEN p.Score > 10 THEN 'Well-Received Answer'
        ELSE 'Standard Answer'
    END AS PostImpactCategory,
    'Active' AS PostStatusFlag, -- Answers generally don't have these specific flags directly
    -- Window function: Rolling average score of user's posts over a 90-day window
    AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN 90 PRECEDING AND CURRENT ROW) AS UserRollingAvgScore90Days,
    -- Window function: Total favorite count for all posts by the user
    SUM(p.FavoriteCount) OVER (PARTITION BY p.OwnerUserId) AS TotalFavoritesByUser,
    LAG(p.CreationDate, 1, p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostCreationDate,
    EXTRACT(EPOCH FROM (p.CreationDate - LAG(p.CreationDate, 1, p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate))) / (60 * 60 * 24) AS DaysSincePreviousPost,
    COUNT(cmt.Id) OVER (PARTITION BY p.Id) AS PostCommentCountWindow,
    CASE WHEN p.Body LIKE '%<pre><code>%' OR p.Body LIKE '%`%`%' THEN TRUE ELSE FALSE END AS HasCodeBlock,
    NULLIF(p.LastEditorUserId, p.OwnerUserId) IS NOT NULL AS EditedByOtherUser,
    t_wiki.Id IS NOT NULL AS PrimaryTagHasWikiPost, -- Will be FALSE as PrimaryTag is NULL for answers
    COALESCE(ARRAY_LENGTH(ARRAY(SELECT unnest FROM unnest(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><')) WHERE unnest ILIKE '%sql%'), 1), 0) AS SQLRelatedTagCount, -- Tags is NULL for answers, so this will evaluate to 0
    (
        SELECT SUM(c_inner.Score)
        FROM Comments c_inner
        WHERE c_inner.PostId = p.Id
          AND c_inner.UserId IS NOT NULL
          AND c_inner.CreationDate > p.CreationDate + INTERVAL '1 hour'
          AND c_inner.Score > 0
    ) AS PostCommentUpvoteSum
FROM
    UserActivitySummary uas
INNER JOIN Posts p ON uas.UserId = p.OwnerUserId
LEFT JOIN PostEditAnalysis pe ON p.Id = pe.PostId
LEFT JOIN PostTaggingContext ptc ON p.Id = ptc.PostId -- ptc.PrimaryTag will be NULL for answers, but the join is consistent
LEFT JOIN Badges b_tag ON uas.UserId = b_tag.UserId
    AND ptc.PrimaryTag IS NOT NULL
    AND b_tag.Name = ptc.PrimaryTag
    AND b_tag.Class = 1
LEFT JOIN Comments cmt ON p.Id = cmt.PostId
LEFT JOIN Tags t_wiki ON ptc.PrimaryTag = t_wiki.TagName AND t_wiki.WikiPostId IS NOT NULL
WHERE
    p.PostTypeId = 2 -- Focus on Answers
    AND uas.TotalBadges > 10 -- Filter for users with many badges
    AND p.CreationDate >= '2022-01-01' -- Recent answers
    AND p.Score > 20 -- Highly scored answers
    AND p.ParentId IS NOT NULL -- Must be an answer to a question
    AND EXISTS (
        -- Correlated subquery: The answer was accepted (VoteTypeId = 1 for AcceptedByOriginator)
        SELECT 1 FROM Votes v_accepted WHERE v_accepted.PostId = p.Id AND v_accepted.VoteTypeId = 1
    )
    AND p.Body IS NOT NULL AND LENGTH(p.Body) > 300 -- Substantial answer body
    AND (SELECT q.Title FROM Posts q WHERE q.Id = p.ParentId) ILIKE '%query%' -- String expression: Parent question title contains 'query'
GROUP BY
    uas.UserId, uas.DisplayName, uas.Reputation, uas.AccountAgeDays, uas.TotalPosts, uas.TotalQuestions, uas.TotalAnswers,
    uas.TotalPostScore, uas.TotalBadges, p.Id, p.PostTypeId, p.Title, p.CreationDate, p.Score, p.ViewCount,
    p.AnswerCount, p.CommentCount, p.FavoriteCount, pe.TotalRevisions, pe.ContentEdits, pe.DistinctEditors,
    pe.ClosureEvents, pe.ReopenEvents, ptc.PrimaryTag, ptc.DuplicateLinkCount, ptc.LinkedPostCount, p.AcceptedAnswerId,
    b_tag.Id, p.Body, p.ClosedDate, p.CommunityOwnedDate, p.LastEditorUserId, p.OwnerUserId, t_wiki.Id
HAVING
    COUNT(DISTINCT cmt.Id) > 1 -- Aggregate condition: At least 1 distinct comment
    AND AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN 90 PRECEDING AND CURRENT ROW) > 10 -- Window function in HAVING
    AND SUM(p.FavoriteCount) OVER (PARTITION BY p.OwnerUserId) > 5 -- Another window function in HAVING

ORDER BY
    Reputation DESC, PostScore DESC
LIMIT 2000;
