-- {"query": "1228.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3481} 

WITH UserEngagement AS (
    -- CTE 1: Aggregates user-level metrics across posts, comments, and votes.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotesGiven,
        SUM(COALESCE(p.ViewCount, 0)) AS TotalPostViews,
        MAX(p.CreationDate) AS LatestPostDate,
        MIN(p.CreationDate) AS EarliestPostDate,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.PostId END) AS PostsEditedCount,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScoreReceived
    FROM Users AS u
    LEFT JOIN Posts AS p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments AS c ON u.Id = c.UserId
    LEFT JOIN Votes AS v ON u.Id = v.UserId
    LEFT JOIN PostHistory AS ph ON u.Id = ph.UserId AND p.Id = ph.PostId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
PostHistoricalMetrics AS (
    -- CTE 2: Captures post-level historical and activity metrics, including a correlated subquery.
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.LastEditDate,
        p.LastActivityDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        COUNT(ph.Id) AS TotalHistoryEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount,
        MAX(CASE WHEN ph.PostHistoryTypeId IN (10, 11) THEN ph.CreationDate ELSE NULL END) AS LastCloseReopenDate,
        -- Correlated subquery to find the creation date of the first edit for a post after its initial creation
        (SELECT MIN(ph_sub.CreationDate)
         FROM PostHistory AS ph_sub
         WHERE ph_sub.PostId = p.Id
           AND ph_sub.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
           AND ph_sub.CreationDate > p.CreationDate) AS FirstEditAfterCreationDate,
        -- Window function: LAG to find the previous post's activity date for the same user
        LAG(p.LastActivityDate, 1, p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevPostActivityDate
    FROM Posts AS p
    LEFT JOIN PostHistory AS ph ON p.Id = ph.PostId
    GROUP BY p.Id, p.PostTypeId, p.CreationDate, p.LastEditDate, p.LastActivityDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.OwnerUserId
),
TopTagsByPost AS (
    -- CTE 3: Extracts and aggregates tags for each post.
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        STRING_AGG(DISTINCT t.TagName, ', ') AS PostTags,
        COUNT(DISTINCT t.Id) AS UniqueTagCount
    FROM Posts AS p
    INNER JOIN Tags AS t ON p.Tags LIKE '%<' || t.TagName || '>%' -- Simplified tag matching using LIKE
    WHERE p.Tags IS NOT NULL AND TRIM(p.Tags) != ''
    GROUP BY p.Id, p.OwnerUserId
)
SELECT
    ue.UserId,
    COALESCE(ue.DisplayName, 'Anonymous User') AS UserDisplayName, -- NULL logic: COALESCE
    ue.Reputation,
    EXTRACT(DAY FROM (NOW() - ue.UserCreationDate)) AS DaysSinceAccountCreation, -- Date calculation
    ue.TotalPosts,
    ue.TotalComments,
    ue.TotalUpVotesGiven,
    ue.TotalDownVotesGiven,
    ue.TotalPostViews,
    phm.PostId,
    pt.Name AS PostTypeName,
    phm.PostCreationDate,
    phm.LastEditDate,
    phm.LastActivityDate,
    phm.Score AS PostScore,
    phm.ViewCount AS PostViewCount,
    phm.AnswerCount,
    phm.CommentCount AS PostCommentCount,
    phm.FavoriteCount AS PostFavoriteCount,
    phm.TotalHistoryEvents,
    phm.EditCount AS PostEditCount,
    COALESCE(phm.LastCloseReopenDate, '1900-01-01 00:00:00') AS PostLastCloseOrReopenEvent, -- NULL logic: COALESCE
    phm.FirstEditAfterCreationDate,
    (EXTRACT(EPOCH FROM (phm.LastActivityDate - phm.PrevPostActivityDate)) / 3600 / 24) AS DaysSincePreviousPostActivity, -- Complicated calculation
    COALESCE(ttbp.PostTags, 'N/A') AS TagsAssociatedWithPost, -- NULL logic: COALESCE
    ttbp.UniqueTagCount,
    -- Window function: Average post score for the user
    AVG(phm.Score) OVER (PARTITION BY ue.UserId) AS AvgPostScoreByUser,
    -- Window function: Rank users by a composite activity score
    RANK() OVER (ORDER BY ue.Reputation DESC, ue.TotalPosts DESC, ue.TotalComments DESC) AS UserRankByActivity,
    -- Complicated predicate/expression: CASE statement for user contribution level
    CASE
        WHEN ue.Reputation > 10000 AND ue.TotalPosts > 50 AND ue.TotalComments > 100 THEN 'High Contributor'
        WHEN ue.Reputation > 1000 AND ue.TotalPosts > 10 AND ue.TotalComments > 20 THEN 'Moderate Contributor'
        ELSE 'Casual Contributor'
    END AS UserContributionLevel,
    -- Complicated calculation: Post engagement score
    (phm.Score * 0.5 + phm.ViewCount * 0.01 + phm.AnswerCount * 2 + phm.FavoriteCount * 3 + phm.EditCount * 0.1) AS PostEngagementScore,
    -- String expression and NULL logic: Generate a checksum suffix for the post ID
    NULLIF(LPAD(ABS(phm.PostId % 1000)::text, 3, '0'), '000') AS PostChecksumSuffix,
    -- Non-correlated subquery (executed per row) to count linked posts
    (SELECT COUNT(DISTINCT l.RelatedPostId)
     FROM PostLinks AS l
     WHERE l.PostId = phm.PostId AND l.LinkTypeId = 1) AS LinkedPostCount,
    -- Non-correlated subquery (executed per row) to count duplicate posts
    (SELECT COUNT(DISTINCT l.RelatedPostId)
     FROM PostLinks AS l
     WHERE l.PostId = phm.PostId AND l.LinkTypeId = 3) AS DuplicatePostCount,
    phm.PostCreationDate >= '2022-01-01' AND phm.PostCreationDate < '2023-01-01' AS IsPostFrom2022, -- Date range predicate
    p_main.Title AS PostTitle,
    SUBSTRING(p_main.Body, 1, 200) AS PostBodyExcerpt, -- String expression: SUBSTRING
    LENGTH(p_main.Body) AS PostBodyLength, -- String expression: LENGTH
    -- Subquery to aggregate Gold Badges earned by the user
    (SELECT STRING_AGG(DISTINCT b.Name, ', ')
     FROM Badges AS b
     WHERE b.UserId = ue.UserId
       AND b.Class = 1 -- Gold badges
       AND b.Date >= ue.UserCreationDate
       AND b.Date < ue.LastAccessDate
     ORDER BY b.Name) AS GoldBadgesEarned,
    -- Subquery to fetch the latest close reason comment for the post
    (SELECT ph_inner.Comment
     FROM PostHistory AS ph_inner
     WHERE ph_inner.PostId = phm.PostId
       AND ph_inner.PostHistoryTypeId = 10 -- Post Closed
       AND ph_inner.Comment IS NOT NULL -- NULL logic: IS NOT NULL
     ORDER BY ph_inner.CreationDate DESC
     LIMIT 1) AS LatestCloseReasonComment
FROM UserEngagement AS ue
INNER JOIN Posts AS p_main ON ue.UserId = p_main.OwnerUserId
INNER JOIN PostHistoricalMetrics AS phm ON p_main.Id = phm.PostId
LEFT JOIN PostTypes AS pt ON phm.PostTypeId = pt.Id -- Outer join
LEFT JOIN TopTagsByPost AS ttbp ON p_main.Id = ttbp.PostId -- Outer join
WHERE
    ue.Reputation > 100 AND ue.TotalPosts > 5
    AND phm.PostCreationDate BETWEEN '2020-01-01' AND '2023-12-31'
    AND (p_main.Tags LIKE '%<sql>%' OR p_main.Tags LIKE '%<database>%') -- Complicated predicate: OR with LIKE
    AND p_main.CommunityOwnedDate IS NULL -- NULL logic: IS NULL
    AND p_main.ClosedDate IS NULL        -- NULL logic: IS NULL
    AND p_main.PostTypeId IN (1, 2) -- Questions and Answers
    AND p_main.ViewCount > 100
    AND phm.Score >= 0

UNION ALL -- Set operator: UNION ALL to combine two different result sets

SELECT
    ue.UserId,
    COALESCE(ue.DisplayName, 'Unknown User') AS UserDisplayName,
    ue.Reputation,
    EXTRACT(DAY FROM (NOW() - ue.UserCreationDate)) AS DaysSinceAccountCreation,
    ue.TotalPosts,
    ue.TotalComments,
    ue.TotalUpVotesGiven,
    ue.TotalDownVotesGiven,
    ue.TotalPostViews,
    phm.PostId,
    pt.Name AS PostTypeName,
    phm.PostCreationDate,
    phm.LastEditDate,
    phm.LastActivityDate,
    phm.Score AS PostScore,
    phm.ViewCount AS PostViewCount,
    phm.AnswerCount,
    phm.CommentCount AS PostCommentCount,
    phm.FavoriteCount AS PostFavoriteCount,
    phm.TotalHistoryEvents,
    phm.EditCount AS PostEditCount,
    COALESCE(phm.LastCloseReopenDate, '1900-01-01 00:00:00') AS PostLastCloseOrReopenEvent,
    phm.FirstEditAfterCreationDate,
    (EXTRACT(EPOCH FROM (phm.LastActivityDate - phm.PrevPostActivityDate)) / 3600 / 24) AS DaysSincePreviousPostActivity,
    COALESCE(ttbp.PostTags, 'N/A') AS TagsAssociatedWithPost,
    ttbp.UniqueTagCount,
    AVG(phm.Score) OVER (PARTITION BY ue.UserId) AS AvgPostScoreByUser,
    RANK() OVER (ORDER BY ue.Reputation DESC, ue.TotalPosts DESC, ue.TotalComments DESC) AS UserRankByActivity,
    'Recent Active Posts' AS UserContributionLevel, -- Different categorization for UNION ALL part
    (phm.Score * 0.5 + phm.ViewCount * 0.01 + phm.AnswerCount * 2 + phm.FavoriteCount * 3 + phm.EditCount * 0.1) AS PostEngagementScore,
    NULLIF(LPAD(ABS(phm.PostId % 1000)::text, 3, '0'), '000') AS PostChecksumSuffix,
    (SELECT COUNT(DISTINCT l.RelatedPostId)
     FROM PostLinks AS l
     WHERE l.PostId = phm.PostId AND l.LinkTypeId = 1) AS LinkedPostCount,
    (SELECT COUNT(DISTINCT l.RelatedPostId)
     FROM PostLinks AS l
     WHERE l.PostId = phm.PostId AND l.LinkTypeId = 3) AS DuplicatePostCount,
    phm.PostCreationDate >= '2022-01-01' AND phm.PostCreationDate < '2023-01-01' AS IsPostFrom2022,
    p_main.Title AS PostTitle,
    SUBSTRING(p_main.Body, 1, 200) AS PostBodyExcerpt,
    LENGTH(p_main.Body) AS PostBodyLength,
    -- Subquery to aggregate Silver Badges earned by the user (different from first part)
    (SELECT STRING_AGG(DISTINCT b.Name, ', ')
     FROM Badges AS b
     WHERE b.UserId = ue.UserId
       AND b.Class = 2 -- Silver badges
       AND b.Date >= ue.UserCreationDate
       AND b.Date < ue.LastAccessDate
     ORDER BY b.Name) AS SilverBadgesEarned,
    (SELECT ph_inner.Comment
     FROM PostHistory AS ph_inner
     WHERE ph_inner.PostId = phm.PostId
       AND ph_inner.PostHistoryTypeId = 10
       AND ph_inner.Comment IS NOT NULL
     ORDER BY ph_inner.CreationDate DESC
     LIMIT 1) AS LatestCloseReasonComment
FROM UserEngagement AS ue
INNER JOIN Posts AS p_main ON ue.UserId = p_main.OwnerUserId
INNER JOIN PostHistoricalMetrics AS phm ON p_main.Id = phm.PostId
LEFT JOIN PostTypes AS pt ON phm.PostTypeId = pt.Id
LEFT JOIN TopTagsByPost AS ttbp ON p_main.Id = ttbp.PostId
WHERE
    ue.LastAccessDate >= NOW() - INTERVAL '6 months' -- Filter for recently active users
    AND ue.Reputation > 500
    AND phm.PostCreationDate >= NOW() - INTERVAL '1 year' -- Filter for recent posts
    AND p_main.PostTypeId = 1 -- Only questions
    AND p_main.AnswerCount > 0
    AND p_main.Score > 5
    AND p_main.LastActivityDate IS NOT NULL

ORDER BY UserRankByActivity, PostEngagementScore DESC
LIMIT 1000;
