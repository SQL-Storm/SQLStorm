-- {"query": "1382.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2996} 

WITH UserEngagement AS (
    -- CTE 1: Select highly reputable users who are recently active and have at least one Gold badge
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS GoldBadgesCount,
        MAX(b.Date) AS LatestBadgeDate,
        SUM(u.UpVotes) AS TotalUpVotesGiven,
        SUM(u.DownVotes) AS TotalDownVotesGiven
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 7500 -- Significant reputation threshold
      AND u.LastAccessDate >= (CURRENT_TIMESTAMP - INTERVAL '1 year') -- Active in the last year
      AND u.AboutMe IS NOT NULL -- Users with some profile description
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
    HAVING COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) >= 1 -- Must have at least one gold badge
),
PostMetrics AS (
    -- CTE 2: Calculate comprehensive metrics for questions, including answer scores, comment counts, and self-edit activity
    SELECT
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.LastEditDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(CASE WHEN c.UserId = p.OwnerUserId THEN 1 ELSE 0 END) AS OwnerCommentsCount,
        AVG(ans.Score) FILTER (WHERE ans.PostTypeId = 2) AS AvgAnswerScore,
        COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (4, 5, 6, 8, 9) AND ph.UserId = p.OwnerUserId) AS SelfEditCount,
        STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><') AS TagArray,
        CASE
            WHEN p.AcceptedAnswerId IS NOT NULL AND p.CommunityOwnedDate IS NULL THEN 'Has Accepted Answer (Not Community Owned)'
            WHEN p.AcceptedAnswerId IS NOT NULL AND p.CommunityOwnedDate IS NOT NULL THEN 'Has Accepted Answer (Community Owned)'
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed Question'
            WHEN p.AnswerCount = 0 AND p.CreationDate < (CURRENT_TIMESTAMP - INTERVAL '30 days') THEN 'Stale Unanswered Question'
            ELSE 'Open Question'
        END AS PostStatus,
        (SELECT COUNT(DISTINCT v.UserId) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 5) AS UniqueFavoritesCount -- Favorite (bookmark) count
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Posts ans ON p.Id = ans.ParentId AND ans.PostTypeId = 2 -- Answers to this question
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE p.PostTypeId = 1 -- Only questions
      AND p.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '5 years') -- Recent enough questions
      AND p.ViewCount > 50 -- Filter out extremely low-view posts for performance
    GROUP BY
        p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.LastEditDate,
        p.Score, p.ViewCount, p.AnswerCount, p.FavoriteCount,
        p.Tags, p.AcceptedAnswerId, p.ClosedDate, p.CommunityOwnedDate
),
TagPerformance AS (
    -- CTE 3: Analyze performance of tags based on associated posts' metrics
    SELECT
        UNNEST(pm.TagArray) AS TagName,
        COUNT(DISTINCT pm.PostId) AS PostCountPerTag,
        AVG(pm.PostScore) AS AvgScorePerTag,
        AVG(pm.ViewCount) AS AvgViewCountPerTag,
        COUNT(DISTINCT pm.OwnerUserId) AS UniqueAuthorsPerTag
    FROM PostMetrics pm
    WHERE pm.PostScore >= 10 OR pm.ViewCount >= 2000 OR pm.FavoriteCount >= 5 -- Focus on more popular posts for tag analysis
    GROUP BY UNNEST(pm.TagArray)
)
-- Main Query: Combine user engagement, post metrics, and tag performance
SELECT
    ue.DisplayName,
    ue.Reputation,
    ue.GoldBadgesCount,
    ue.LatestBadgeDate,
    ue.TotalUpVotesGiven,
    ue.TotalDownVotesGiven,
    pm.PostId,
    COALESCE(pm.Title, 'Untitled Post - No Title Provided') AS PostTitle,
    pm.PostCreationDate,
    pm.PostScore,
    pm.ViewCount,
    pm.AnswerCount,
    pm.CommentCount,
    pm.OwnerCommentsCount,
    pm.SelfEditCount,
    pm.AvgAnswerScore,
    pm.PostStatus,
    pm.UniqueFavoritesCount,
    -- Join with TagPerformance for tag-specific insights
    tp.PostCountPerTag,
    tp.AvgScorePerTag,
    tp.AvgViewCountPerTag,
    tp.UniqueAuthorsPerTag,
    -- Window function: Rank each user's posts by 'impact score'
    ROW_NUMBER() OVER (PARTITION BY ue.UserId ORDER BY (pm.PostScore * 1.5 + pm.ViewCount * 0.05 + pm.AnswerCount * 3 + pm.CommentCount * 1 + COALESCE(pm.AvgAnswerScore, 0) * 2 + pm.UniqueFavoritesCount * 0.75) DESC, pm.PostCreationDate DESC) AS UserPostImpactRank,
    -- Window function: Calculate average view count for all posts by this user
    AVG(pm.ViewCount) OVER (PARTITION BY ue.UserId) AS UserAvgPostViewCount,
    -- Window function: Calculate the difference in days between the current post's creation and the previous post's creation by the same user
    EXTRACT(DAY FROM (pm.PostCreationDate - LAG(pm.PostCreationDate, 1, pm.PostCreationDate) OVER (PARTITION BY ue.UserId ORDER BY pm.PostCreationDate))) AS DaysSincePreviousPost,
    -- Correlated subquery: Find the most common post type history event for this user (e.g., most common edit type they perform)
    (
        SELECT pht.Name
        FROM PostHistory ph_inner
        JOIN PostHistoryTypes pht ON ph_inner.PostHistoryTypeId = pht.Id
        WHERE ph_inner.UserId = ue.UserId
        GROUP BY pht.Name
        ORDER BY COUNT(ph_inner.Id) DESC
        LIMIT 1
    ) AS MostCommonHistoryEventTypeByOwner,
    -- Complicated calculation: "Total Post Engagement Score"
    (pm.PostScore * 0.8) + (pm.ViewCount * 0.02) + (pm.AnswerCount * 2.5) + (pm.CommentCount * 1.2) + COALESCE(pm.AvgAnswerScore, 0) * 1.5 + (pm.UniqueFavoritesCount * 1.0) AS TotalPostEngagementScore,
    -- String expression: Analyze length of post title and identify if it's a "How to" or "Best way" question
    LENGTH(COALESCE(pm.Title, '')) AS TitleLength,
    (pm.Title ILIKE '%how to%' OR pm.Title ILIKE '%best way%') AS IsHowToOrBestWayQuestion,
    COALESCE(EXTRACT(EPOCH FROM (pm.LastEditDate - pm.PostCreationDate)) / 3600, 0) AS HoursToFirstEditOrZero -- Hours from creation to first edit, or 0 if no edit
FROM UserEngagement ue
JOIN PostMetrics pm ON ue.UserId = pm.OwnerUserId
LEFT JOIN TagPerformance tp ON tp.TagName = ANY(pm.TagArray) -- Join on relevant tags
WHERE pm.PostScore >= 10 OR pm.FavoriteCount >= 2 OR pm.CommentCount >= 5 -- Filter for more engaged posts
  AND NOT EXISTS (
      -- Correlated subquery to exclude posts that had a significant title/body edit by a non-owner within 24 hours of creation
      SELECT 1
      FROM PostHistory ph_outer
      WHERE ph_outer.PostId = pm.PostId
        AND ph_outer.UserId IS NOT NULL
        AND ph_outer.UserId != pm.OwnerUserId
        AND ph_outer.PostHistoryTypeId IN (4, 5) -- Edit Title, Edit Body
        AND ph_outer.CreationDate < (pm.PostCreationDate + INTERVAL '24 hours')
  )
UNION ALL
-- Second Branch: Focus on highly impactful posts (high views, score, answers) regardless of owner's engagement profile
-- This branch includes posts potentially from deleted users or those not meeting the strict 'UserEngagement' criteria.
SELECT
    NULL AS DisplayName, -- Owner details are not the focus here
    NULL AS Reputation,
    NULL AS GoldBadgesCount,
    NULL AS LatestBadgeDate,
    NULL AS TotalUpVotesGiven,
    NULL AS TotalDownVotesGiven,
    p_high.Id AS PostId,
    COALESCE(p_high.Title, 'Highly Viewed/Scored Post - No Title Provided') AS PostTitle,
    p_high.CreationDate AS PostCreationDate,
    p_high.Score AS PostScore,
    p_high.ViewCount,
    p_high.AnswerCount,
    COUNT(c_high.Id) AS CommentCount,
    0 AS OwnerCommentsCount, -- Not tracking owner comments in this branch
    0 AS SelfEditCount, -- Not tracking self edits
    AVG(ans_high.Score) FILTER (WHERE ans_high.PostTypeId = 2) AS AvgAnswerScore,
    CASE
        WHEN p_high.AcceptedAnswerId IS NOT NULL THEN 'Has Accepted Answer'
        WHEN p_high.ClosedDate IS NOT NULL THEN 'Closed Question'
        ELSE 'Open Question'
    END AS PostStatus,
    (SELECT COUNT(DISTINCT v.UserId) FROM Votes v WHERE v.PostId = p_high.Id AND v.VoteTypeId = 5) AS UniqueFavoritesCount,
    NULL AS PostCountPerTag, -- Not joining with TagPerformance here
    NULL AS AvgScorePerTag,
    NULL AS AvgViewCountPerTag,
    NULL AS UniqueAuthorsPerTag,
    ROW_NUMBER() OVER (ORDER BY p_high.ViewCount DESC, p_high.Score DESC, p_high.AnswerCount DESC) AS UserPostImpactRank, -- Overall rank here
    NULL AS UserAvgPostViewCount,
    NULL AS DaysSincePreviousPost,
    NULL AS MostCommonHistoryEventTypeByOwner,
    -- Different impact formula for this branch, emphasizing pure popularity
    (p_high.Score * 0.9) + (p_high.ViewCount * 0.03) + (p_high.AnswerCount * 4) + (COUNT(c_high.Id) * 1.5) AS TotalPostEngagementScore,
    LENGTH(COALESCE(p_high.Title, '')) AS TitleLength,
    (p_high.Title ILIKE '%performance%' OR p_high.Title ILIKE '%optimization%' OR p_high.Title ILIKE '%security%') AS ContainsPopularKeyword,
    COALESCE(EXTRACT(EPOCH FROM (p_high.LastEditDate - p_high.CreationDate)) / 3600, 0) AS HoursToFirstEditOrZero
FROM Posts p_high
LEFT JOIN Comments c_high ON p_high.Id = c_high.PostId
LEFT JOIN Posts ans_high ON p_high.Id = ans_high.ParentId AND ans_high.PostTypeId = 2
WHERE p_high.PostTypeId = 1
  AND p_high.ViewCount > 75000 -- Very high view count threshold
  AND p_high.Score > 75 -- High score threshold
  AND p_high.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '7 years')
  AND p_high.OwnerUserId IS NULL -- Specifically target posts without a known active owner (e.g., deleted users or community posts)
GROUP BY
    p_high.Id, p_high.Title, p_high.CreationDate, p_high.Score, p_high.ViewCount,
    p_high.AnswerCount, p_high.AcceptedAnswerId, p_high.ClosedDate, p_high.LastEditDate
ORDER BY TotalPostEngagementScore DESC, PostCreationDate DESC
LIMIT 1000; -- Limit the final output to manage result set size for benchmarking purposes
