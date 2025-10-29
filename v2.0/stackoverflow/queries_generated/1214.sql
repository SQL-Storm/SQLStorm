-- {"query": "1214.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2916} 

WITH UserActivitySummary AS (
    -- Summarizes user-level activity including post counts, scores, and comment counts.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScore,
        SUM(COALESCE(p.ViewCount, 0)) AS TotalPostViews,
        COUNT(DISTINCT c.Id) AS TotalComments,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) AS AvgQuestionScore,
        MAX(p.CreationDate) AS LatestPostDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
UserBadgeStats AS (
    -- Aggregates badge statistics for each user, categorizing by class.
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(b.Date) AS LatestBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
PostModerationHistory AS (
    -- Tracks various moderation and voting activities for posts, including closure, deletion, edits, and rollbacks.
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        MAX(CASE WHEN ph.PostHistoryTypeId IN (10, 12, 14, 19) THEN 1 ELSE 0 END) AS WasClosedDeletedLockedOrProtected, -- Post closed, deleted, locked, or protected
        MAX(CASE WHEN ph.PostHistoryTypeId IN (11, 13, 15, 20) THEN 1 ELSE 0 END) AS WasReopenedUndeletedUnlockedOrUnprotected, -- Post reopened, undeleted, unlocked, or unprotected
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownVoteCount,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpVoteCount,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.Id END) AS EditHistoryCount, -- Edit Title, Body, Tags
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (7, 8, 9) THEN ph.Id END) AS RollbackHistoryCount -- Rollback Title, Body, Tags
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3) -- UpMod, DownMod
    GROUP BY p.Id, p.OwnerUserId
),
UserPostPerformanceExtended AS (
    -- Calculates post performance metrics with window functions for user-specific context.
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.Title,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.Tags,
        p.LastActivityDate,
        p.LastEditDate,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostScore,
        NTILE(10) OVER (ORDER BY p.Score DESC) AS GlobalScoreDecileRank,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS UserAveragePostScore
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL AND p.PostTypeId IN (1, 2) -- Questions or Answers
),
TopInfluentialAndControversialPosts AS (
    -- Identifies posts by influential users that exhibit signs of controversy or neglect.
    SELECT
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.TotalPosts,
        uas.TotalQuestions,
        uas.TotalAnswers,
        COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
        (uas.Reputation * 1.0 / GREATEST(1, uas.TotalPosts)) AS AvgReputationPerPost,
        CASE
            WHEN ubs.GoldBadges >= 5 AND uas.TotalQuestions >= 10 THEN 'High Achiever & Contributor'
            WHEN uas.TotalPosts > 50 AND uas.AvgQuestionScore > 10 THEN 'Prolific & Engaged'
            WHEN ubs.TotalBadges IS NULL THEN 'New or Inactive'
            ELSE 'Active Contributor'
        END AS UserCategory,
        uppe.PostId,
        uppe.PostTypeId,
        uppe.Title AS PostTitle,
        uppe.PostCreationDate,
        uppe.PostScore,
        uppe.ViewCount AS PostViewCount,
        uppe.CommentCount AS PostCommentCount,
        uppe.FavoriteCount AS PostFavoriteCount,
        pmh.DownVoteCount,
        pmh.UpVoteCount,
        (pmh.DownVoteCount * 1.0 / NULLIF(pmh.UpVoteCount + pmh.DownVoteCount, 0)) AS DownvoteRatio,
        COALESCE(pmh.WasClosedDeletedLockedOrProtected, 0) AS PostWasModeratedNegatively,
        COALESCE(pmh.WasReopenedUndeletedUnlockedOrUnprotected, 0) AS PostWasModeratedPositively,
        pmh.EditHistoryCount,
        pmh.RollbackHistoryCount,
        uppe.PreviousPostScore,
        uppe.GlobalScoreDecileRank,
        uppe.UserAveragePostScore,
        (uppe.PostScore * 1.0 / NULLIF(uppe.UserAveragePostScore, 0)) AS ScoreVsUserAverageRatio,
        (
            SELECT STRING_AGG(unnest_tags, ', ')
            FROM unnest(string_to_array(SUBSTRING(uppe.Tags, 2, LENGTH(uppe.Tags)-2), '><')) AS unnest_tags
            WHERE LENGTH(unnest_tags) > 0
        ) AS ProcessedPostTags,
        (
            SELECT MAX(ph_edit.CreationDate)
            FROM PostHistory ph_edit
            WHERE ph_edit.PostId = uppe.PostId
              AND ph_edit.UserId = uppe.OwnerUserId
              AND ph_edit.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Body, Tags
              AND ph_edit.CreationDate = uppe.LastEditDate -- Correlated subquery for latest owner edit
        ) AS LatestOwnerEditDate,
        (
            SELECT COUNT(DISTINCT co.Id)
            FROM Comments co
            WHERE co.PostId = uppe.PostId
              AND co.CreationDate > uppe.PostCreationDate
              AND co.UserId IS NOT NULL
              AND LENGTH(co.Text) > 50 -- Correlated subquery for significant comments
        ) AS SignificantCommentCountForPost,
        'Influential & Controversial User Post' AS AnalysisType
    FROM UserActivitySummary uas
    LEFT JOIN UserBadgeStats ubs ON uas.UserId = ubs.UserId
    INNER JOIN UserPostPerformanceExtended uppe ON uas.UserId = uppe.OwnerUserId
    LEFT JOIN PostModerationHistory pmh ON uppe.PostId = pmh.PostId
    WHERE
        uas.Reputation >= 5000
        AND uas.TotalPosts >= 20
        AND (
            (pmh.WasClosedDeletedLockedOrProtected = 1 AND COALESCE(pmh.WasReopenedUndeletedUnlockedOrUnprotected, 0) = 0) OR
            (pmh.DownVoteCount * 1.0 / NULLIF(pmh.UpVoteCount + pmh.DownVoteCount, 0) > 0.4) OR
            (uppe.PostTypeId = 1 AND uppe.AnswerCount = 0 AND uppe.PostCreationDate < (NOW() - INTERVAL '2 year') AND uppe.LastActivityDate < (NOW() - INTERVAL '1 year'))
        )
),
HighActivityFlaggedPosts AS (
    -- Identifies posts with high activity (views, comments, edits) that also have moderation flags or rollbacks.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        NULL::bigint AS TotalPosts,
        NULL::bigint AS TotalQuestions,
        NULL::bigint AS TotalAnswers,
        NULL::smallint AS GoldBadges,
        NULL::numeric AS AvgReputationPerPost,
        'High Activity Flagged Post' AS UserCategory,
        p.Id AS PostId,
        p.PostTypeId,
        p.Title AS PostTitle,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.CommentCount AS PostCommentCount,
        p.FavoriteCount AS PostFavoriteCount,
        pmh.DownVoteCount,
        pmh.UpVoteCount,
        (pmh.DownVoteCount * 1.0 / NULLIF(pmh.UpVoteCount + pmh.DownVoteCount, 0)) AS DownvoteRatio,
        COALESCE(pmh.WasClosedDeletedLockedOrProtected, 0) AS PostWasModeratedNegatively,
        COALESCE(pmh.WasReopenedUndeletedUnlockedOrUnprotected, 0) AS PostWasModeratedPositively,
        pmh.EditHistoryCount,
        pmh.RollbackHistoryCount,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostScore,
        NTILE(10) OVER (ORDER BY p.Score DESC) AS GlobalScoreDecileRank,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS UserAveragePostScore,
        (p.Score * 1.0 / NULLIF(AVG(p.Score) OVER (PARTITION BY p.OwnerUserId), 0)) AS ScoreVsUserAverageRatio,
        (
            SELECT STRING_AGG(unnest_tags, ', ')
            FROM unnest(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) AS unnest_tags
            WHERE LENGTH(unnest_tags) > 0
        ) AS ProcessedPostTags,
        (
            SELECT MAX(ph_edit.CreationDate)
            FROM PostHistory ph_edit
            WHERE ph_edit.PostId = p.Id
              AND ph_edit.UserId = p.OwnerUserId
              AND ph_edit.PostHistoryTypeId IN (4, 5, 6)
              AND ph_edit.CreationDate = p.LastEditDate
        ) AS LatestOwnerEditDate,
        NULL::bigint AS SignificantCommentCountForPost, -- Placeholder to match column count and type for UNION ALL
        'High Activity Flagged Post' AS AnalysisType
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN PostModerationHistory pmh ON p.Id = pmh.PostId
    WHERE
        p.OwnerUserId IS NOT NULL
        AND p.PostTypeId IN (1, 2)
        AND p.ViewCount >= 2000
        AND p.CommentCount >= 15
        AND pmh.EditHistoryCount >= 5
        AND (
            pmh.WasClosedDeletedLockedOrProtected = 1 OR
            pmh.RollbackHistoryCount >= 2
        )
)
-- Combines the two sets of analyzed posts and orders them by reputation and post score.
SELECT * FROM TopInfluentialAndControversialPosts
UNION ALL
SELECT * FROM HighActivityFlaggedPosts
ORDER BY Reputation DESC NULLS LAST, PostScore DESC
LIMIT 2000;
