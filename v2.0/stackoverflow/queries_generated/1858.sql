-- {"query": "1858.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2992} 

WITH UserEngagement AS (
    -- CTE 1: Summarize core user engagement metrics, including calculated average post lifespan and total edits by the user.
    -- Includes non-correlated subquery for TotalEditActions.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.UpVotes AS TotalUpVotesGiven,
        u.DownVotes AS TotalDownVotesGiven,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        COALESCE(SUM(p.Score), 0) AS TotalPostScoreReceived,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalUpVotesReceivedOnPosts,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS TotalDownVotesReceivedOnPosts,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        MAX(u.LastAccessDate) AS LastActivity,
        AVG(EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate)) / 3600.0) FILTER (WHERE p.LastActivityDate IS NOT NULL AND p.CreationDate IS NOT NULL) AS AvgPostLifespanHours,
        (SELECT COUNT(ph.Id) FROM PostHistory ph WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId IN (4,5,6)) AS TotalEditActionsByUser
    FROM
        Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON p.Id = v.PostId -- Votes received on user's posts
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes, u.CreationDate
    HAVING
        COUNT(DISTINCT p.Id) > 5 -- Only consider users with at least 5 posts
        AND u.Reputation > 1000
),
PostVersionComplexity AS (
    -- CTE 2: Analyze post edit complexity, comment density, and link types for individual posts.
    -- Uses LAG() and ROW_NUMBER() window functions.
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        LENGTH(p.Body) AS BodyLength,
        COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (4, 5, 6)) AS PostEditCount, -- Only specific edit types
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 11) THEN ph.Id END) AS CloseReopenEvents,
        SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateLinkCount, -- Number of times this post is linked as a duplicate of others
        AVG(c.Score) AS AvgCommentScore,
        COUNT(c.Id) AS TotalPostComments,
        (CAST(COUNT(c.Id) AS DECIMAL) / NULLIF(LENGTH(p.Body), 0)) * 100 AS CommentDensityPercent,
        LAG(ph.CreationDate, 1, p.CreationDate) OVER (PARTITION BY p.Id ORDER BY ph.CreationDate) AS PreviousPostEditDate,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY ph.CreationDate DESC) AS rn_last_edit_hist -- For finding the very last edit event
    FROM
        Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6, 10, 11)
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN PostLinks pl ON p.Id = pl.RelatedPostId AND pl.LinkTypeId = 3
    GROUP BY
        p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.Body
),
WeightedTagInfluence AS (
    -- CTE 3: Calculate influence of tags based on associated post scores and view counts.
    -- Uses string functions for cleaning tag names.
    SELECT
        LOWER(TRIM(REPLACE(REPLACE(unnest(string_to_array(substring(p.Tags, 2, LENGTH(p.Tags) - 2), '><')), '&lt;', '<'), '&gt;', '>'))) AS TagName,
        SUM(p.Score * p.ViewCount) AS TagWeightedScore,
        COUNT(DISTINCT p.Id) AS TagPostCount
    FROM
        Posts p
    WHERE
        p.Tags IS NOT NULL
        AND p.PostTypeId = 1 -- Only questions have tags in this context
    GROUP BY
        1
    HAVING
        COUNT(DISTINCT p.Id) > 100 -- Only consider tags with substantial usage
),
PostTagInfluence AS (
    -- CTE 4: For each question post, identify its most influential tags.
    -- Uses a LATERAL JOIN for efficient unnesting and STRING_AGG with FILTER for conditional aggregation.
    SELECT
        p.Id AS PostId,
        STRING_AGG(DISTINCT wti.TagName, ', ') FILTER (WHERE wti.TagWeightedScore > 1000000) AS TopInfluentialTags
    FROM
        Posts p
    LEFT JOIN LATERAL (
        SELECT
            LOWER(TRIM(REPLACE(REPLACE(unnest_tag.tag_name, '&lt;', '<'), '&gt;', '>'))) AS CleanTagName
        FROM
            unnest(string_to_array(substring(p.Tags, 2, LENGTH(p.Tags) - 2), '><')) AS unnest_tag(tag_name)
    ) AS unnested_tags ON TRUE
    LEFT JOIN WeightedTagInfluence wti ON unnested_tags.CleanTagName = wti.TagName
    WHERE
        p.Tags IS NOT NULL
        AND p.PostTypeId = 1 -- Only questions have tags
    GROUP BY p.Id
),
HighActivityPostsCombined AS (
    -- CTE 5: Uses UNION ALL to combine posts identified by different high-activity criteria.
    -- This demonstrates a set operator to merge results from different logical paths.
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.CommentCount,
        'HighViewQuestion' AS ActivityType
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.ViewCount > 10000 AND p.Score > 50
    UNION ALL
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.CommentCount,
        'HighlyScoredAnswer' AS ActivityType
    FROM Posts p
    WHERE p.PostTypeId = 2 AND p.Score > 100 AND p.CommentCount > 5
)
-- Main Query: Integrates all CTEs to identify high-impact contributors, their key posts, and associated metrics.
-- Includes complex predicates, further window functions, and correlated subqueries.
SELECT
    ue.DisplayName,
    ue.Reputation,
    ue.TotalPosts,
    ue.TotalQuestions,
    ue.TotalAnswers,
    ue.TotalBadges,
    ue.TotalEditActionsByUser,
    hap.PostId AS HighImpactPostId,
    hap.PostTypeId AS HighImpactPostType,
    hap.Score AS HighImpactPostScore,
    hap.ViewCount AS HighImpactPostViews,
    pvc.PostEditCount AS HighImpactPostEdits,
    pvc.TotalPostComments,
    pvc.CommentDensityPercent,
    pvc.DuplicateLinkCount,
    pvc.PreviousPostEditDate, -- From LAG window function
    ph_last_edit.CreationDate AS LastPostEditDate,
    DENSE_RANK() OVER (ORDER BY ue.Reputation DESC, ue.TotalPostScoreReceived DESC, ue.TotalEditActionsByUser DESC) AS OverallContributorRank,
    AVG(pvc.Score) OVER (PARTITION BY pvc.PostTypeId) AS AvgScoreForPostType,
    MAX(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS HasGoldBadge, -- MAX required due to multiple badge rows per user
    pti.TopInfluentialTags,
    (
        -- Correlated subquery to count high-scoring answers within the first month for *this specific post*
        SELECT
            COUNT(DISTINCT pv.Id)
        FROM
            Posts pv
        WHERE
            pv.ParentId = hap.PostId
            AND pv.Score > 5
            AND pv.CreationDate BETWEEN hap.CreationDate AND hap.CreationDate + INTERVAL '1 month'
            AND pv.OwnerUserId IS NOT NULL
            AND EXISTS (SELECT 1 FROM Users u_sub WHERE u_sub.Id = pv.OwnerUserId AND u_sub.Reputation > 500)
    ) AS HighScoringAnswersInFirstMonth,
    COALESCE(ph_close_reason.Comment, 'N/A') AS PostCloseReason, -- NULL handling for close reason
    ABS(EXTRACT(EPOCH FROM (hap.CreationDate - ue.UserCreationDate)) / (60*60*24.0)) AS DaysSinceUserCreationToPost, -- Calculation
    CASE
        WHEN hap.ActivityType = 'HighViewQuestion' AND pvc.PostEditCount > 5 AND pvc.CommentDensityPercent > 1.0 THEN 'Highly Evolving & Discussed Question'
        WHEN hap.ActivityType = 'HighlyScoredAnswer' AND pvc.TotalPostComments > 10 THEN 'Highly Discussed Answer'
        WHEN hap.ActivityType = 'HighViewQuestion' THEN 'High Visibility Question'
        ELSE 'Other Active Contribution'
    END AS PostCategoryDescription -- Complex CASE expression
FROM
    UserEngagement ue
INNER JOIN HighActivityPostsCombined hap ON ue.UserId = hap.OwnerUserId
INNER JOIN PostVersionComplexity pvc ON hap.PostId = pvc.PostId
LEFT JOIN PostHistory ph_last_edit ON pvc.PostId = ph_last_edit.PostId
    AND ph_last_edit.PostHistoryTypeId IN (4,5,6)
    AND pvc.rn_last_edit_hist = 1 -- Join to get the exact last edit record
LEFT JOIN PostHistory ph_close_reason ON pvc.PostId = ph_close_reason.PostId
    AND ph_close_reason.PostHistoryTypeId = 10 -- Only join for post close events
LEFT JOIN Badges b ON ue.UserId = b.UserId
LEFT JOIN PostTagInfluence pti ON hap.PostId = pti.PostId
WHERE
    hap.CreationDate > (NOW() - INTERVAL '2 years')
    AND ue.TotalUpVotesReceivedOnPosts > ue.TotalDownVotesReceivedOnPosts * 2 -- Complicated predicate based on user votes
    AND NOT EXISTS ( -- Correlated subquery: Exclude deleted posts
        SELECT 1
        FROM PostHistory ph_deleted
        WHERE ph_deleted.PostId = hap.PostId
          AND ph_deleted.PostHistoryTypeId = 12
    )
    AND EXISTS ( -- Correlated subquery: user must have at least one gold or silver badge
        SELECT 1
        FROM Badges b_sub
        WHERE b_sub.UserId = ue.UserId
          AND b_sub.Class IN (1, 2)
    )
    AND (pvc.CommentDensityPercent > 0.5 OR pvc.PostEditCount > 3) -- Complex OR predicate
GROUP BY
    ue.DisplayName, ue.Reputation, ue.TotalPosts, ue.TotalQuestions, ue.TotalAnswers, ue.TotalBadges, ue.TotalEditActionsByUser, ue.UserCreationDate,
    hap.PostId, hap.PostTypeId, hap.Score, hap.ViewCount, hap.CommentCount, hap.ActivityType,
    pvc.PostEditCount, pvc.TotalPostComments, pvc.CommentDensityPercent, pvc.DuplicateLinkCount, pvc.PreviousPostEditDate,
    ph_last_edit.CreationDate, ph_close_reason.Comment, pti.TopInfluentialTags
ORDER BY
    OverallContributorRank ASC, HighImpactPostScore DESC, HighScoringAnswersInFirstMonth DESC
LIMIT 100;
