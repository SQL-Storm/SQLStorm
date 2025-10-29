-- {"query": "1574.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2951} 

WITH UserActivitySummary AS (
    -- Summarize user activity: post counts, scores, views, and distinct edit counts
    -- This CTE involves conditional aggregation and joins for posts and their edit history.
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        -- Calculate average scores, handling potential NULLs if a user has no posts of a certain type
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) AS AvgQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) AS AvgAnswerScore,
        SUM(COALESCE(p.ViewCount, 0)) AS TotalViews,
        COUNT(DISTINCT ph_edit.Id) AS TotalEdits -- Count unique history IDs for actual edits (Title, Body, Tags)
    FROM Posts p
    LEFT JOIN PostHistory ph_edit ON p.Id = ph_edit.PostId AND ph_edit.PostHistoryTypeId IN (4,5,6)
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserBadgeSummary AS (
    -- Summarize user badges by class (Gold, Silver, Bronze)
    -- This CTE uses conditional aggregation to count badge types.
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgeCount,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadgeCount,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgeCount,
        COUNT(b.Id) AS TotalBadgeCount
    FROM Badges b
    GROUP BY b.UserId
),
RankedUserPostEdits AS (
    -- Identify the latest body/rollback edit for each post using a window function (ROW_NUMBER)
    -- This helps in later joining to get the latest edit details efficiently.
    SELECT
        ph.PostId,
        ph.CreationDate AS EditDate,
        ph.UserDisplayName AS EditorDisplayName,
        ph.Text AS EditedContentSnippet,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC, ph.Id DESC) AS rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (5, 8) -- Edit Body, Rollback Body
),
UserPostHighlights AS (
    -- Finds the single most popular question and most controversial answer for each user.
    -- This CTE extensively uses correlated subqueries (SELECT ... FROM ... WHERE u.Id = ...)
    -- which are often performance bottlenecks and good for benchmarking.
    SELECT
        u.Id AS UserId,
        -- Most popular question (by ViewCount, then Score)
        (SELECT p_pq.Id FROM Posts p_pq WHERE p_pq.OwnerUserId = u.Id AND p_pq.PostTypeId = 1 ORDER BY p_pq.ViewCount DESC, p_pq.Score DESC, p_pq.Id DESC LIMIT 1) AS MostPopularQuestionId,
        (SELECT p_pq.Title FROM Posts p_pq WHERE p_pq.OwnerUserId = u.Id AND p_pq.PostTypeId = 1 ORDER BY p_pq.ViewCount DESC, p_pq.Score DESC, p_pq.Id DESC LIMIT 1) AS MostPopularQuestionTitle,
        (SELECT p_pq.ViewCount FROM Posts p_pq WHERE p_pq.OwnerUserId = u.Id AND p_pq.PostTypeId = 1 ORDER BY p_pq.ViewCount DESC, p_pq.Score DESC, p_pq.Id DESC LIMIT 1) AS MostPopularQuestionViews,
        -- Most controversial answer (by DownVote count)
        (SELECT p_ca.Id FROM Posts p_ca JOIN Votes v_ca ON p_ca.Id = v_ca.PostId WHERE p_ca.OwnerUserId = u.Id AND p_ca.PostTypeId = 2 AND v_ca.VoteTypeId = 3 GROUP BY p_ca.Id ORDER BY COUNT(v_ca.Id) DESC, p_ca.Id DESC LIMIT 1) AS MostControversialAnswerId,
        (SELECT p_ca.Score FROM Posts p_ca JOIN Votes v_ca ON p_ca.Id = v_ca.PostId WHERE p_ca.OwnerUserId = u.Id AND p_ca.PostTypeId = 2 AND v_ca.VoteTypeId = 3 GROUP BY p_ca.Id ORDER BY COUNT(v_ca.Id) DESC, p_ca.Id DESC LIMIT 1) AS MostControversialAnswerScore
    FROM Users u
    -- Only consider users who have at least one question or one answer to avoid unnecessary subquery execution
    WHERE EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1)
       OR EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2)
)
-- Main query part 1: Identify "Engaged Users" based on specific criteria
SELECT
    'EngagedUser' AS UserCategory,
    u.Id AS UserId,
    u.DisplayName AS UserName,
    -- String expression: Extract a snippet from AboutMe, handling NULLs
    SUBSTRING(COALESCE(u.AboutMe, 'No "About Me" provided.'), 1, 150) AS AboutMeExcerpt,
    u.Reputation,
    uas.TotalPosts,
    uas.QuestionCount,
    uas.AnswerCount,
    ROUND(COALESCE(uas.AvgQuestionScore, 0), 2) AS AvgQScore,
    ROUND(COALESCE(uas.AvgAnswerScore, 0), 2) AS AvgAScore,
    ubs.GoldBadgeCount,
    ubs.TotalBadgeCount,
    uph.MostPopularQuestionId,
    uph.MostPopularQuestionTitle,
    uph.MostPopularQuestionViews,
    -- NULL logic: COALESCE for date and string fields from the latest edit
    COALESCE(lqe.EditDate, '1970-01-01'::timestamp) AS PopQ_LastEditDate,
    COALESCE(lqe.EditorDisplayName, 'Community') AS PopQ_LastEditor,
    -- String expression: Extract snippet from edited body
    COALESCE(LEFT(lqe.EditedContentSnippet, 200), 'No recent body edit info') AS PopQ_EditBodySnippet,
    uph.MostControversialAnswerId,
    uph.MostControversialAnswerScore,
    -- Correlated subquery for comment count on controversial answer
    COALESCE((SELECT COUNT(c.Id) FROM Comments c WHERE c.PostId = uph.MostControversialAnswerId), 0) AS ControversialA_CommentCount,
    -- Complicated predicate/expression: Check if the most popular question has an accepted answer
    (CASE WHEN EXISTS (SELECT 1 FROM Posts p WHERE p.Id = uph.MostPopularQuestionId AND p.AcceptedAnswerId IS NOT NULL) THEN 'Has Accepted Answer' ELSE 'No Accepted Answer' END) AS HasAcceptedAnswerStatus,
    -- Complex calculation: "Engagement Score" combining multiple user metrics with weights, handling NULLs
    CAST((u.UpVotes * 0.5 + u.DownVotes * 0.2 + COALESCE(u.Views, 0) * 0.01 + COALESCE(uas.TotalEdits, 0) * 1.5 + COALESCE(ubs.TotalBadgeCount, 0) * 5 +
         COALESCE(uph.MostPopularQuestionViews, 0) * 0.05 - (COALESCE(uph.MostControversialAnswerScore, 0) * -1) * 0.1) AS INT) AS EngagementScore,
    -- Window function: Rank users by their total activity within this category
    RANK() OVER (ORDER BY (COALESCE(uas.TotalPosts,0) + COALESCE(uas.TotalEdits,0) + COALESCE(ubs.TotalBadgeCount,0)) DESC, u.Reputation DESC) AS ActivityRank
FROM Users u
JOIN UserActivitySummary uas ON u.Id = uas.UserId
JOIN UserBadgeSummary ubs ON u.Id = ubs.UserId
LEFT JOIN UserPostHighlights uph ON u.Id = uph.UserId -- Outer join for posts highlights (some users might not have Q/A)
LEFT JOIN RankedUserPostEdits lqe ON uph.MostPopularQuestionId = lqe.PostId AND lqe.rn = 1 -- Outer join for latest edit details
WHERE
    uas.QuestionCount >= 1 AND
    uas.AnswerCount >= 1 AND
    ubs.GoldBadgeCount >= 1 AND
    -- Complicated predicate: Average Question Score must be strictly greater than Average Answer Score, handling NULLs
    COALESCE(uas.AvgQuestionScore, 0) > COALESCE(uas.AvgAnswerScore, -1000) AND
    u.CreationDate > '2015-01-01' AND -- Date filtering
    COALESCE(u.Views, 0) > 50 AND
    u.Reputation > 1000 AND
    u.Location IS NOT NULL AND -- NULL logic predicate
    u.DisplayName LIKE 'A%' AND -- String expression predicate
    LENGTH(COALESCE(u.AboutMe, '')) > 20 -- String expression predicate (length)

UNION ALL -- Set operator: Combine with another distinct user group

-- Main query part 2: Identify "Moderation Involved Users" based on post history actions
SELECT
    'ModerationInvolvedUser' AS UserCategory,
    u.Id AS UserId,
    u.DisplayName AS UserName,
    SUBSTRING(COALESCE(u.AboutMe, 'No "About Me" provided.'), 1, 150) AS AboutMeExcerpt,
    u.Reputation,
    uas.TotalPosts,
    uas.QuestionCount,
    uas.AnswerCount,
    ROUND(COALESCE(uas.AvgQuestionScore, 0), 2) AS AvgQScore,
    ROUND(COALESCE(uas.AvgAnswerScore, 0), 2) AS AvgAScore,
    ubs.GoldBadgeCount,
    ubs.TotalBadgeCount,
    NULL AS MostPopularQuestionId, -- Not relevant for this category
    NULL AS MostPopularQuestionTitle,
    NULL AS MostPopularQuestionViews,
    NULL AS PopQ_LastEditDate,
    NULL AS PopQ_LastEditor,
    NULL AS PopQ_EditBodySnippet,
    NULL AS MostControversialAnswerId, -- Not relevant for this category
    NULL AS MostControversialAnswerScore,
    NULL AS ControversialA_CommentCount,
    'N/A' AS HasAcceptedAnswerStatus,
    -- Complex calculation: "Engagement Score" for moderation involvement
    CAST((u.UpVotes * 0.1 + u.DownVotes * 0.5 + ph_mod.CloseReopenCount * 10 + ph_mod.DeletionUndeletionCount * 15 +
         (CASE WHEN COALESCE(u.WebsiteUrl, '') LIKE '%github%' THEN 100 ELSE 0 END)) AS INT) AS EngagementScore, -- Conditional string check in calculation
    RANK() OVER (ORDER BY (ph_mod.CloseReopenCount + ph_mod.DeletionUndeletionCount) DESC, u.Reputation DESC) AS ActivityRank
FROM Users u
JOIN UserActivitySummary uas ON u.Id = uas.UserId
JOIN UserBadgeSummary ubs ON u.Id = ubs.UserId
JOIN (
    -- Subquery for user moderation actions (Close/Reopen, Delete/Undelete)
    SELECT
        ph.UserId,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (10, 11) THEN 1 ELSE 0 END) AS CloseReopenCount,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (12, 13) THEN 1 ELSE 0 END) AS DeletionUndeletionCount
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
    GROUP BY ph.UserId
) ph_mod ON u.Id = ph_mod.UserId
WHERE
    (ph_mod.CloseReopenCount > 5 OR ph_mod.DeletionUndeletionCount > 2) AND
    u.Reputation > 500 AND
    u.LastAccessDate > NOW() - INTERVAL '1 year' AND
    (u.EmailHash IS NULL OR u.EmailHash NOT LIKE '%00000%') AND -- NULL logic and string exclusion
    u.AccountId IS NOT NULL -- NULL logic predicate
ORDER BY UserCategory, EngagementScore DESC
LIMIT 1000;
