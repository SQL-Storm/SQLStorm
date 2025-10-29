-- {"query": "1146.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3491} 

WITH PostInteractions AS (
    -- CTE to gather all linked and duplicated posts, unifying their representation
    -- Uses UNION ALL to combine two types of post relationships from PostLinks
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        p.OwnerUserId AS PostOwnerUserId,
        pr.OwnerUserId AS RelatedPostOwnerUserId,
        'LINKED_TO' AS InteractionType,
        pl.CreationDate AS InteractionDate
    FROM PostLinks pl
    JOIN Posts p ON pl.PostId = p.Id
    JOIN Posts pr ON pl.RelatedPostId = pr.Id
    WHERE pl.LinkTypeId = 1 -- 'Linked' posts
    UNION ALL
    SELECT
        pl.RelatedPostId AS PostId, -- For 'Duplicate' relations, we consider the target post as the primary
        pl.PostId AS RelatedPostId,
        pr.OwnerUserId AS PostOwnerUserId,
        p.OwnerUserId AS RelatedPostOwnerUserId,
        'DUPLICATE_OF' AS InteractionType,
        pl.CreationDate AS InteractionDate
    FROM PostLinks pl
    JOIN Posts p ON pl.PostId = p.Id
    JOIN Posts pr ON pl.RelatedPostId = pr.Id
    WHERE pl.LinkTypeId = 3 -- 'Duplicate' posts
),
UserActivitySummary AS (
    -- CTE to summarize general user activity and calculate some initial metrics
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.CreationDate AS UserCreationDate,
        u.Reputation,
        u.Views AS TotalProfileViews,
        u.UpVotes AS TotalUpVotesGiven,
        u.DownVotes AS TotalDownVotesGiven,
        u.LastAccessDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COUNT(DISTINCT c.Id) AS TotalComments,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScore, -- NULL logic for post score
        MAX(p.LastActivityDate) AS LastPostActivity,
        -- Complex calculation: Average score per post, handling division by zero with NULLIF
        COALESCE(CAST(SUM(p.Score) AS NUMERIC) / NULLIF(COUNT(p.Id), 0), 0) AS AvgPostScorePerPost,
        -- Window function: Average reputation of users created in the same month
        AVG(u.Reputation) OVER (PARTITION BY DATE_TRUNC('month', u.CreationDate)) AS AvgMonthlyNewUserReputation
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id, u.DisplayName, u.CreationDate, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.LastAccessDate
),
PostContentDetails AS (
    -- CTE to extract and process details for questions and answers
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate AS PostCreationDate,
        p.Tags,
        p.FavoriteCount,
        p.AnswerCount,
        p.ClosedDate,
        p.LastEditDate,
        -- String expression: Truncated title or beginning of body if title is NULL
        COALESCE(p.Title, LEFT(p.Body, 100) || '...') AS PostTitleSnippet,
        -- Window function: Rank posts by score within a user's posts of the same type
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId, p.PostTypeId ORDER BY p.Score DESC, p.CreationDate DESC) AS rn_post_by_user_type,
        -- Window function: Calculate the cumulative score for a user's posts over time
        SUM(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS UserCumulativePostScore
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) -- Only Questions and Answers
),
ModerationInfluence AS (
    -- CTE to track user involvement in moderation-related PostHistory events
    SELECT
        ph.UserId,
        COUNT(DISTINCT ph.PostId) AS PostsAffectedByModeration,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (10, 12, 14, 19) THEN 1 ELSE 0 END) AS ModerationActionsTakenCount, -- Close, Delete, Lock, Protect
        SUM(CASE WHEN ph.PostHistoryTypeId IN (11, 13, 15, 20) THEN 1 ELSE 0 END) AS ModerationReversalsMadeCount, -- Reopen, Undelete, Unlock, Unprotect
        -- Correlated subquery: Check if a user has ever closed a post that was later reopened by a different user
        (
            SELECT EXISTS (
                SELECT 1
                FROM PostHistory ph_inner
                WHERE ph_inner.PostId = ph.PostId
                  AND ph_inner.PostHistoryTypeId = 10 -- Post Closed
                  AND ph_inner.UserId = ph.UserId
                  AND EXISTS (
                        SELECT 1
                        FROM PostHistory ph_reopen
                        WHERE ph_reopen.PostId = ph_inner.PostId
                          AND ph_reopen.PostHistoryTypeId = 11 -- Post Reopened
                          AND ph_reopen.UserId IS DISTINCT FROM ph_inner.UserId -- Reopened by a different user
                  )
            )
        ) AS HasContestedCloseAction
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
      AND ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20)
    GROUP BY ph.UserId
),
UserTagContributions AS (
    -- CTE to determine users' top tags based on post scores and counts
    SELECT
        pcd.OwnerUserId AS UserId,
        -- String expression: Split tags string into individual tags
        TRIM(UNNEST(string_to_array(SUBSTRING(pcd.Tags, 2, LENGTH(pcd.Tags) - 2), '><'))) AS TagName,
        COUNT(DISTINCT pcd.PostId) AS TagPostCount,
        SUM(pcd.Score) AS TagTotalScore,
        -- Window function: Rank tags for each user based on their score contribution
        ROW_NUMBER() OVER (PARTITION BY pcd.OwnerUserId ORDER BY SUM(pcd.Score) DESC, COUNT(DISTINCT pcd.PostId) DESC) AS rn_tag_by_user
    FROM PostContentDetails pcd
    WHERE pcd.Tags IS NOT NULL AND pcd.Tags != ''
    GROUP BY pcd.OwnerUserId, TRIM(UNNEST(string_to_array(SUBSTRING(pcd.Tags, 2, LENGTH(pcd.Tags) - 2), '><')))
),
UserBadgeSummary AS (
    -- CTE to summarize badges obtained by users
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
AggregatedLinkedPosts AS (
    -- CTE to summarize linked/duplicated post interactions for each post
    SELECT
        pi.PostId,
        pi.PostOwnerUserId AS UserId,
        COUNT(pi.RelatedPostId) AS TotalRelatedPosts,
        SUM(CASE WHEN pi.InteractionType = 'DUPLICATE_OF' THEN 1 ELSE 0 END) AS TotalDuplicatesOf,
        MAX(pi.InteractionDate) AS LastPostRelationDate,
        -- Window function: Rank posts by their total number of linked/duplicated relations
        DENSE_RANK() OVER (ORDER BY COUNT(pi.RelatedPostId) DESC) AS PostRelationRank
    FROM PostInteractions pi
    GROUP BY pi.PostId, pi.PostOwnerUserId
    HAVING COUNT(pi.RelatedPostId) >= 2 -- Only consider posts with at least 2 relations
),
UserCommentActivity AS (
    -- CTE to analyze user comment patterns, including a recent activity check
    SELECT
        c.UserId,
        COUNT(c.Id) AS UserTotalComments,
        MAX(c.CreationDate) AS LastCommentDate,
        -- Correlated subquery in SELECT: check if the user has any comments with score > 1 in the last 90 days
        (
            SELECT EXISTS (
                SELECT 1
                FROM Comments c_sub
                WHERE c_sub.UserId = c.UserId
                  AND c_sub.Score > 1
                  AND c_sub.CreationDate >= (CURRENT_DATE - INTERVAL '90 days')
            )
        ) AS HasRecentHighScoreComments
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
)
-- Main query: Combines all the pre-processed data from CTEs
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.TotalPosts,
    uas.TotalQuestions,
    uas.TotalAnswers,
    uas.TotalComments,
    uca.UserTotalComments,
    uca.LastCommentDate,
    uca.HasRecentHighScoreComments,
    uas.AvgPostScorePerPost,
    uas.LastPostActivity,
    uas.AvgMonthlyNewUserReputation,
    mi.PostsAffectedByModeration,
    mi.ModerationActionsTakenCount,
    mi.ModerationReversalsMadeCount,
    mi.HasContestedCloseAction, -- Boolean result from correlated subquery
    COALESCE(ubs.TotalBadges, 0) AS TotalBadges,
    COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
    -- Complicated calculation: Reputation per badge, gracefully handling zero badges
    CASE
        WHEN COALESCE(ubs.TotalBadges, 0) > 0 THEN ROUND(CAST(uas.Reputation AS NUMERIC) / ubs.TotalBadges, 2)
        ELSE 0.0
    END AS ReputationPerBadge,
    -- Aggregate top 3 tags for the user using conditional aggregation (MAX/CASE)
    MAX(CASE WHEN utc.rn_tag_by_user = 1 THEN utc.TagName ELSE NULL END) AS TopTag1,
    MAX(CASE WHEN utc.rn_tag_by_user = 1 THEN utc.TagTotalScore ELSE NULL END) AS TopTag1Score,
    MAX(CASE WHEN utc.rn_tag_by_user = 2 THEN utc.TagName ELSE NULL END) AS TopTag2,
    MAX(CASE WHEN utc.rn_tag_by_user = 2 THEN utc.TagTotalScore ELSE NULL END) AS TopTag2Score,
    MAX(CASE WHEN utc.rn_tag_by_user = 3 THEN utc.TagName ELSE NULL END) AS TopTag3,
    MAX(CASE WHEN utc.rn_tag_by_user = 3 THEN utc.TagTotalScore ELSE NULL END) AS TopTag3Score,
    -- Window function: Overall rank of user based on their total post score
    DENSE_RANK() OVER (ORDER BY uas.TotalPostScore DESC, uas.Reputation DESC) AS OverallUserScoreRank,
    -- String expression and date calculations for user tenure summary
    CONCAT(
        'Member for ',
        DATE_PART('year', AGE(CURRENT_DATE, uas.UserCreationDate)),
        ' years, last access on ',
        TO_CHAR(uas.LastAccessDate, 'YYYY-MM-DD HH24:MI')
    ) AS UserTenureAndAccessSummary,
    -- Subquery for a specific count: High-impact, open questions by the user, with complicated predicates
    (
        SELECT COUNT(DISTINCT pcd_sub.PostId)
        FROM PostContentDetails pcd_sub
        WHERE pcd_sub.OwnerUserId = uas.UserId
          AND pcd_sub.PostTypeId = 1 -- Questions
          AND pcd_sub.Score > 50
          AND pcd_sub.ViewCount > 10000
          AND pcd_sub.AnswerCount IS NOT NULL AND pcd_sub.AnswerCount > 3
          AND pcd_sub.ClosedDate IS NULL
          AND pcd_sub.LastEditDate >= (CURRENT_DATE - INTERVAL '6 months') -- Edited recently
    ) AS HighImpactOpenQuestionsCount,
    -- Aggregated information about linked/duplicated posts
    COALESCE(alp.TotalRelatedPosts, 0) AS PostsWithRelations,
    COALESCE(alp.TotalDuplicatesOf, 0) AS PostsMarkedAsDuplicateSource,
    alp.LastPostRelationDate,
    alp.PostRelationRank,
    -- Conditional expression based on user's profile views vs. system average
    CASE
        WHEN uas.TotalProfileViews > (SELECT AVG(Views) FROM Users WHERE Views IS NOT NULL) THEN 'Above Average Views'
        WHEN uas.TotalProfileViews < (SELECT AVG(Views) FROM Users WHERE Views IS NOT NULL) THEN 'Below Average Views'
        ELSE 'Average Views'
    END AS ProfileViewCategory
FROM UserActivitySummary uas
LEFT JOIN ModerationInfluence mi ON uas.UserId = mi.UserId
LEFT JOIN UserBadgeSummary ubs ON uas.UserId = ubs.UserId
LEFT JOIN UserCommentActivity uca ON uas.UserId = uca.UserId
LEFT JOIN ( -- Subquery to aggregate top tags for joining with the main result
    SELECT
        UserId,
        MAX(CASE WHEN rn_tag_by_user = 1 THEN TagName END) AS TopTag1,
        MAX(CASE WHEN rn_tag_by_user = 1 THEN TagTotalScore END) AS TopTag1Score,
        MAX(CASE WHEN rn_tag_by_user = 2 THEN TagName END) AS TopTag2,
        MAX(CASE WHEN rn_tag_by_user = 2 THEN TagTotalScore END) AS TopTag2Score,
        MAX(CASE WHEN rn_tag_by_user = 3 THEN TagName END) AS TopTag3,
        MAX(CASE WHEN rn_tag_by_user = 3 THEN TagTotalScore END) AS TopTag3Score
    FROM UserTagContributions
    GROUP BY UserId
) AS utc_agg ON uas.UserId = utc_agg.UserId
LEFT JOIN AggregatedLinkedPosts alp ON uas.UserId = alp.UserId
WHERE uas.TotalPosts > 0 OR uas.TotalComments > 0 OR uas.TotalProfileViews > 0 -- Filter for active/visible users
ORDER BY uas.Reputation DESC, OverallUserScoreRank ASC, uas.UserId
LIMIT 500;
