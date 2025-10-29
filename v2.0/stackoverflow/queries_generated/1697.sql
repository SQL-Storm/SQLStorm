-- {"query": "1697.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2919} 

WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        SUM(p.Score) AS TotalPostScoreGiven,
        AVG(p.Score) AS AvgPostScore,
        COUNT(c.Id) AS TotalCommentsMade,
        MAX(b.CreationDate) AS LatestBadgeDate,
        -- Correlated subquery to count Gold badges
        (SELECT COUNT(DISTINCT b2.Id) FROM Badges b2 WHERE b2.UserId = u.Id AND b2.Class = 1) AS GoldBadgesCount,
        -- Window function: rank users by reputation among those who joined in the same month
        RANK() OVER (PARTITION BY DATE_TRUNC('month', u.CreationDate) ORDER BY u.Reputation DESC) AS MonthlyReputationRank,
        -- Window function: Time difference in hours between a user's first and last post
        EXTRACT(EPOCH FROM (MAX(p.CreationDate) - MIN(p.CreationDate))) / 3600 AS UserActivitySpanHours
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
PostContentAnalysis AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.AcceptedAnswerId,
        p.ParentId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.Body,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount AS DirectCommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.CommunityOwnedDate,
        p.LastEditDate,
        p.LastActivityDate,
        -- Complicated string expression for Tags
        CASE
            WHEN p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2
            THEN string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><')
            ELSE ARRAY[]::VARCHAR(50)[]
        END AS TagArray,
        -- String expression and NULL logic for title
        COALESCE(p.Title, 'Untitled Post (ID: ' || CAST(p.Id AS VARCHAR) || ')') AS DisplayTitle,
        -- Calculation: Score to View ratio, with NULL handling
        CAST(p.Score AS NUMERIC) / NULLIF(p.ViewCount, 0) AS ScoreToViewRatio,
        -- Calculation: Density of comments in post body, handling NULL body
        CAST(p.CommentCount AS NUMERIC) / NULLIF(LENGTH(COALESCE(p.Body, '')), 0) AS CommentDensityInBody,
        -- Window function: Average score of posts by the same owner, up to this post
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RollingAvgOwnerScore,
        -- Window function: Time since previous post by the same owner
        EXTRACT(EPOCH FROM (p.CreationDate - LAG(p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate))) / 3600 AS HoursSincePreviousPost,
        -- Window function: Rank posts by score within their PostTypeId
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate DESC) AS PostScoreRankInType
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) -- Focus on Questions and Answers
    AND p.CreationDate >= (NOW() - INTERVAL '5 year') -- Limit data to last 5 years for performance
),
PostHistoryEvents AS (
    SELECT
        ph.PostId,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS LastClosedDate, -- Post Closed
        MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate END) AS LastReopenedDate, -- Post Reopened
        MAX(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.CreationDate END) AS LastContentEditDate, -- Edit Title/Body/Tags
        -- String aggregation for history comments by moderators (assuming moderator actions have a UserId)
        STRING_AGG(CASE WHEN ph.Comment IS NOT NULL AND ph.UserId IS NOT NULL THEN ph.Comment ELSE NULL END, ' | ') FILTER (WHERE ph.PostHistoryTypeId IN (10, 11, 14, 15)) AS ModeratorActionComments,
        -- Correlated subquery: check if post was ever migrated away
        (SELECT COUNT(*) FROM PostHistory ph2 WHERE ph2.PostId = ph.PostId AND ph2.PostHistoryTypeId = 35) > 0 AS WasMigratedAway,
        -- Window function: Most recent significant history event type
        FIRST_VALUE(ph.PostHistoryTypeId) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS LatestHistoryEventType
    FROM PostHistory ph
    WHERE ph.CreationDate >= (NOW() - INTERVAL '5 year')
    GROUP BY ph.PostId
),
TopCommentsPerPost AS (
    SELECT
        c.PostId,
        c.Id AS TopCommentId,
        c.Text AS TopCommentText,
        c.Score AS TopCommentScore,
        c.CreationDate AS TopCommentDate,
        ROW_NUMBER() OVER (PARTITION BY c.PostId ORDER BY c.Score DESC, c.CreationDate DESC) AS rn
    FROM Comments c
    WHERE c.CreationDate >= (NOW() - INTERVAL '5 year') -- Match main post filter
)
-- Main Query: Combine information to find highly engaged content and users with complex filtering and scoring
SELECT
    pca.PostId,
    pca.DisplayTitle,
    pca.PostTypeId,
    pca.PostCreationDate,
    pca.PostScore,
    pca.ViewCount,
    pca.AnswerCount,
    pca.DirectCommentCount,
    pca.FavoriteCount,
    uas.DisplayName AS OwnerDisplayName,
    uas.Reputation AS OwnerReputation,
    uas.GoldBadgesCount AS OwnerGoldBadges,
    pca.ScoreToViewRatio,
    pca.CommentDensityInBody,
    pca.RollingAvgOwnerScore,
    pca.HoursSincePreviousPost,
    pca.ClosedDate,
    pca.CommunityOwnedDate,
    phe.LastClosedDate,
    phe.LastReopenedDate,
    phe.LastContentEditDate,
    phe.ModeratorActionComments,
    phe.WasMigratedAway,
    -- NULL logic and complicated expressions for post status
    COALESCE(
        CASE
            WHEN pca.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN pca.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            WHEN phe.LastReopenedDate IS NOT NULL AND (phe.LastClosedDate IS NULL OR phe.LastReopenedDate > phe.LastClosedDate) THEN 'Reopened'
            ELSE 'Open'
        END, 'Unknown Status'
    ) AS PostStatus,
    -- Nested CASE for categorizing post engagement
    CASE
        WHEN pca.PostTypeId = 1 THEN
            CASE
                WHEN pca.PostScore >= 100 AND pca.AnswerCount >= 5 AND pca.ViewCount >= 10000 THEN 'Very Hot Question'
                WHEN pca.PostScore >= 50 AND pca.AnswerCount >= 2 AND pca.ViewCount >= 5000 THEN 'Hot Question'
                WHEN pca.ScoreToViewRatio > 0.1 AND pca.DirectCommentCount >= 10 THEN 'Engaging Question'
                ELSE 'Regular Question'
            END
        WHEN pca.PostTypeId = 2 THEN
            CASE
                WHEN pca.PostScore >= 50 AND pca.ScoreToViewRatio > 0.2 AND pca.AcceptedAnswerId IS NOT NULL THEN 'Highly Valued Accepted Answer'
                WHEN pca.PostScore >= 10 AND pca.DirectCommentCount >= 3 THEN 'Discussed Answer'
                ELSE 'Regular Answer'
            END
        ELSE 'Other Post Type'
    END AS PostEngagementCategory,
    -- Join with accepted answer details using a self-join on PostContentAnalysis CTE
    aa.PostScore AS AcceptedAnswerScore,
    aa_owner.DisplayName AS AcceptedAnswerOwner,
    aa.PostCreationDate AS AcceptedAnswerCreationDate,
    -- Most upvoted comment details
    tcp.TopCommentText,
    tcp.TopCommentScore,
    -- String array and boolean predicates for tag analysis (PostgreSQL specific array operators)
    ARRAY_TO_STRING(pca.TagArray, ', ') AS TagsList,
    (pca.TagArray && ARRAY['sql', 'database', 'performance', 'indexing', 'query-optimization']) AS ContainsRelevantTechTag,
    (pca.TagArray && ARRAY['opinion-based', 'subjective', 'discussion', 'community-wiki']) AS IsSubjectiveTagPresent,
    -- Calculation: Age of post in days
    EXTRACT(DAY FROM (NOW() - pca.PostCreationDate)) AS PostAgeDays,
    -- Calculation: Time from creation to last activity in hours
    EXTRACT(EPOCH FROM (pca.LastActivityDate - pca.PostCreationDate)) / 3600 AS TimeToLastActivityHours,
    -- Overall impact score: a complex calculation with NULL handling
    (
        (pca.PostScore * 2.5) +
        (COALESCE(pca.ViewCount, 0) * 0.001) +
        (COALESCE(pca.AnswerCount, 0) * 5.0) +
        (COALESCE(pca.DirectCommentCount, 0) * 1.5) +
        (COALESCE(pca.FavoriteCount, 0) * 3.0) +
        (CASE WHEN pca.AcceptedAnswerId IS NOT NULL THEN 10 ELSE 0 END) +
        (CASE WHEN phe.WasMigratedAway THEN -5 ELSE 0 END) + -- Penalize migrated posts
        (COALESCE(uas.Reputation, 0) * 0.0001) + -- Add a small component from owner reputation
        (CASE WHEN pca.LastEditDate > (NOW() - INTERVAL '30 day') THEN 2.0 ELSE 0 END) -- Boost for recently edited posts
    ) AS OverallImpactScore
FROM PostContentAnalysis pca
LEFT JOIN UserActivitySummary uas ON pca.OwnerUserId = uas.UserId
LEFT JOIN PostHistoryEvents phe ON pca.PostId = phe.PostId
LEFT JOIN PostContentAnalysis aa ON pca.AcceptedAnswerId = aa.PostId AND pca.PostTypeId = 1 -- Only questions have AcceptedAnswerId
LEFT JOIN UserActivitySummary aa_owner ON aa.OwnerUserId = aa_owner.UserId
LEFT JOIN TopCommentsPerPost tcp ON pca.PostId = tcp.PostId AND tcp.rn = 1
WHERE
    pca.PostCreationDate >= (NOW() - INTERVAL '3 year') -- Focus on more recent posts for active engagement
    AND uas.TotalPosts > 5 -- Filter for more active users
    AND (pca.PostTypeId = 1 OR (pca.PostTypeId = 2 AND pca.PostScore > 0)) -- Only questions or positive score answers
    AND pca.PostScore >= 5 -- Filter out low-quality posts initially
    AND NOT (pca.ClosedDate IS NOT NULL AND pca.PostScore < 10 AND pca.CommentCount < 3) -- Exclude low-score, closed, low-comment posts
    AND (pca.TagArray && ARRAY['sql', 'postgresql', 'mysql', 'database', 'performance'] OR pca.Title ILIKE '%database%' OR pca.Body ILIKE '%sql%') -- Filter for specific tech topics
    AND (EXTRACT(MONTH FROM pca.PostCreationDate) IN (6, 7, 8) OR EXTRACT(YEAR FROM pca.PostCreationDate) % 2 = 0) -- Seasonal/yearly filtering pattern
ORDER BY
    OverallImpactScore DESC,
    pca.PostCreationDate DESC
LIMIT 1000;
