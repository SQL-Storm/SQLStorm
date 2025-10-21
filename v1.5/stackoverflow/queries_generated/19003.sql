-- {"query": "19003.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3757} 

WITH UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Views AS UserViews,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(COALESCE(p.ViewCount, 0)) AS TotalPostViews,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScore,
        COUNT(DISTINCT c.Id) AS TotalComments,
        SUM(COALESCE(c.Score, 0)) AS TotalCommentScore,
        MAX(p.LastActivityDate) AS LastPostActivity,
        MAX(c.CreationDate) AS LastCommentActivity
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
        u.Views, u.UpVotes, u.DownVotes
),
PostHistoryIntervals AS (
    -- Calculate time intervals between consecutive post history events for each post
    SELECT
        ph.PostId,
        ph.CreationDate AS CurrentEventDate,
        -- Use LAG to get the previous history event date, defaulting to post creation if no previous
        LAG(ph.CreationDate, 1, p.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PreviousEventDate,
        EXTRACT(EPOCH FROM (ph.CreationDate - LAG(ph.CreationDate, 1, p.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate))) AS SecondsSinceLastEvent
    FROM PostHistory ph
    JOIN Posts p ON ph.PostId = p.Id
),
AvgPostHistoryIntervals AS (
    -- Aggregate the average time between history events per post
    SELECT
        PostId,
        AVG(SecondsSinceLastEvent) AS AvgSecondsBetweenEvents
    FROM PostHistoryIntervals
    WHERE SecondsSinceLastEvent IS NOT NULL AND SecondsSinceLastEvent > 0 -- Exclude initial creation or instantaneous events
    GROUP BY PostId
),
PostHistoricalMetrics AS (
    -- Collect various metrics and historical flags for each post
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.AcceptedAnswerId,
        p.ClosedDate,
        p.CommunityOwnedDate,
        COUNT(DISTINCT ph_edit.Id) AS EditCount,
        COUNT(DISTINCT ph_revert.Id) AS RevertCount,
        MAX(CASE WHEN ph_close.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS WasClosed,
        MAX(CASE WHEN ph_reopen.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS WasReopened,
        MAX(CASE WHEN ph_delete.PostHistoryTypeId = 12 THEN 1 ELSE 0 END) AS WasDeleted,
        SUM(CASE WHEN vt.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN vt.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        (SELECT COUNT(DISTINCT pl.RelatedPostId) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 1) AS LinkedPostCount, -- Correlated subquery for linked posts
        (SELECT COUNT(DISTINCT pl.RelatedPostId) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS DuplicatePostCount, -- Correlated subquery for duplicate posts
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE NULL END) OVER (PARTITION BY p.OwnerUserId) AS AvgAnswerCountForUser, -- Window function: average answers for a user's questions
        api.AvgSecondsBetweenEvents
    FROM Posts p
    LEFT JOIN PostHistory ph_edit ON p.Id = ph_edit.PostId AND ph_edit.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Body, Tags
    LEFT JOIN PostHistory ph_revert ON p.Id = ph_revert.PostId AND ph_revert.PostHistoryTypeId IN (7, 8, 9) -- Rollback Title, Body, Tags
    LEFT JOIN PostHistory ph_close ON p.Id = ph_close.PostId AND ph_close.PostHistoryTypeId = 10 -- Post Closed
    LEFT JOIN PostHistory ph_reopen ON p.Id = ph_reopen.PostId AND ph_reopen.PostHistoryTypeId = 11 -- Post Reopened
    LEFT JOIN PostHistory ph_delete ON p.Id = ph_delete.PostId AND ph_delete.PostHistoryTypeId = 12 -- Post Deleted
    LEFT JOIN Votes vt ON p.Id = vt.PostId AND vt.VoteTypeId IN (2, 3) -- UpMod, DownMod
    LEFT JOIN AvgPostHistoryIntervals api ON p.Id = api.PostId
    GROUP BY
        p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount,
        p.AnswerCount, p.FavoriteCount, p.AcceptedAnswerId, p.ClosedDate,
        p.CommunityOwnedDate, api.AvgSecondsBetweenEvents
),
PostTagAnalysis AS (
    -- Extract and unnest tags for questions
    SELECT
        p.Id AS PostId,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName, -- String expression: parse tags
        p.PostTypeId,
        p.Score
    FROM Posts p
    WHERE p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2 AND p.PostTypeId = 1 -- NULL logic, string length check
),
AggregatedTagMetrics AS (
    -- Calculate metrics per tag
    SELECT
        pta.TagName,
        COUNT(DISTINCT pta.PostId) AS TaggedQuestionCount,
        AVG(pta.Score) AS AvgTagScore,
        SUM(pta.Score) AS TotalTagScore
    FROM PostTagAnalysis pta
    GROUP BY pta.TagName
),
UserBadgeSummary AS (
    -- Summarize badge counts per user
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM Badges b
    GROUP BY b.UserId
)
-- Main query: Identify high-impact user-post combinations
SELECT
    ue.DisplayName,
    ue.Reputation,
    ue.TotalPosts,
    ue.TotalQuestions,
    ue.TotalAnswers,
    ue.TotalPostViews,
    ue.TotalPostScore,
    COALESCE(ubs.GoldBadges, 0) AS GoldBadges, -- NULL logic: default to 0 for users without badges
    COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
    COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
    pm.PostId,
    pm.PostTypeId,
    pm.PostScore,
    pm.ViewCount,
    pm.AnswerCount,
    pm.EditCount,
    pm.RevertCount,
    pm.WasClosed,
    pm.WasDeleted,
    pm.LinkedPostCount,
    pm.DuplicatePostCount,
    atm.TagName AS MostFrequentTagName,
    atm.TaggedQuestionCount AS MostFrequentTagCount,
    atm.AvgTagScore AS MostFrequentTagAvgScore,
    (EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - ue.UserCreationDate)) / (3600 * 24 * 365.25))::numeric(10,2) AS YearsSinceCreation, -- Date calculation
    (pm.AvgSecondsBetweenEvents / 3600)::numeric(10,2) AS AvgTimeBetweenEventsHours, -- Complex calculation
    CASE -- Complicated predicate/expression/calculation
        WHEN ue.Reputation > 5000 AND ue.TotalPosts > 50 AND COALESCE(ubs.GoldBadges, 0) > 0 THEN 'High Achiever'
        WHEN ue.Reputation > 1000 AND ue.TotalPosts > 20 AND ue.TotalQuestions > 5 AND pm.PostTypeId = 1 AND pm.WasClosed = 0 THEN 'Active Contributor'
        WHEN pm.RevertCount > pm.EditCount / 2 AND pm.EditCount > 3 AND pm.PostTypeId = 1 THEN 'Contentious Question'
        WHEN pm.WasClosed = 1 AND pm.WasReopened = 0 AND pm.WasDeleted = 0 AND pm.PostTypeId = 1 THEN 'Closed Unresolved Question'
        ELSE 'Other'
    END AS UserPostCategory,
    RANK() OVER (PARTITION BY pm.PostTypeId ORDER BY pm.PostScore DESC, pm.ViewCount DESC) AS RankByPostTypeScore, -- Window function
    NTILE(5) OVER (ORDER BY ue.Reputation DESC, ue.TotalPostScore DESC) AS ReputationQuintile, -- Window function
    (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = pm.PostId AND v.VoteTypeId = 8) AS AvgBountyAmount, -- Correlated subquery
    COALESCE(NULLIF(ue.UserViews, 0), 1) * 1.0 / COALESCE(NULLIF(ue.TotalPosts, 0), 1) AS ViewsPerPostRatio, -- NULL logic & ratio calculation
    ( -- Correlated subquery with NULL logic and EXISTS
        SELECT
            CASE
                WHEN EXISTS (SELECT 1 FROM Posts ap WHERE ap.Id = pm.AcceptedAnswerId AND ap.Score > 50) THEN 'High Score Accepted Answer'
                WHEN pm.AcceptedAnswerId IS NOT NULL THEN 'Accepted Answer'
                ELSE 'No Accepted Answer'
            END
    ) AS AcceptedAnswerStatus
FROM UserEngagement ue
LEFT JOIN UserBadgeSummary ubs ON ue.UserId = ubs.UserId -- Outer join
INNER JOIN PostHistoricalMetrics pm ON ue.UserId = pm.OwnerUserId
LEFT JOIN PostTagAnalysis pta_main ON pm.PostId = pta_main.PostId
LEFT JOIN AggregatedTagMetrics atm ON pta_main.TagName = atm.TagName
WHERE
    ue.Reputation > 1000
    AND ue.LastAccessDate >= CURRENT_TIMESTAMP - INTERVAL '2 year' -- Date comparison
    AND (
        pm.PostScore > 50
        OR (pm.ViewCount > 5000 AND pm.AnswerCount > 2) -- Complicated predicate
    )
    AND pm.EditCount > 1
    AND pm.RevertCount <= pm.EditCount / 2
    AND NOT EXISTS ( -- Correlated subquery for exclusion
        SELECT 1
        FROM PostHistory ph_locked
        WHERE ph_locked.PostId = pm.PostId
          AND ph_locked.PostHistoryTypeId = 14 -- Post Locked
          AND ph_locked.CreationDate > pm.PostCreationDate + INTERVAL '1 month'
    )
    AND pm.PostTypeId IN (1, 2) -- Only Questions and Answers
    AND ue.DisplayName IS NOT NULL -- NULL logic
    AND ue.DisplayName NOT LIKE 'Community%' -- String expression
    AND (
        pm.PostCreationDate BETWEEN ue.UserCreationDate AND ue.UserCreationDate + INTERVAL '5 year' -- Date range
    )
    AND ( -- String expressions with OR
        ue.DisplayName LIKE '%Dev%'
        OR ue.DisplayName LIKE '%Tech%'
        OR ue.DisplayName LIKE '%Engineer%'
        OR ue.DisplayName LIKE '%Coder%'
    )

UNION ALL -- Set operator: Combine with another query for different criteria

-- Identify low-impact or newer posts from less established users
SELECT
    ue.DisplayName,
    ue.Reputation,
    ue.TotalPosts,
    ue.TotalQuestions,
    ue.TotalAnswers,
    ue.TotalPostViews,
    ue.TotalPostScore,
    COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
    COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
    pm.PostId,
    pm.PostTypeId,
    pm.PostScore,
    pm.ViewCount,
    pm.AnswerCount,
    pm.EditCount,
    pm.RevertCount,
    pm.WasClosed,
    pm.WasDeleted,
    pm.LinkedPostCount,
    pm.DuplicatePostCount,
    atm.TagName AS MostFrequentTagName,
    atm.TaggedQuestionCount AS MostFrequentTagCount,
    atm.AvgTagScore AS MostFrequentTagAvgScore,
    (EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - ue.UserCreationDate)) / (3600 * 24 * 365.25))::numeric(10,2) AS YearsSinceCreation,
    (pm.AvgSecondsBetweenEvents / 3600)::numeric(10,2) AS AvgTimeBetweenEventsHours,
    'Low Impact Post' AS UserPostCategory,
    RANK() OVER (PARTITION BY pm.PostTypeId ORDER BY pm.PostScore ASC, pm.ViewCount ASC) AS RankByPostTypeScore, -- Window function
    NTILE(5) OVER (ORDER BY ue.Reputation DESC, ue.TotalPostScore DESC) AS ReputationQuintile, -- Window function
    (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = pm.PostId AND v.VoteTypeId = 8) AS AvgBountyAmount,
    COALESCE(NULLIF(ue.UserViews, 0), 1) * 1.0 / COALESCE(NULLIF(ue.TotalPosts, 0), 1) AS ViewsPerPostRatio,
    (
        SELECT
            CASE
                WHEN EXISTS (SELECT 1 FROM Posts ap WHERE ap.Id = pm.AcceptedAnswerId AND ap.Score > 50) THEN 'High Score Accepted Answer'
                WHEN pm.AcceptedAnswerId IS NOT NULL THEN 'Accepted Answer'
                ELSE 'No Accepted Answer'
            END
    ) AS AcceptedAnswerStatus
FROM UserEngagement ue
LEFT JOIN UserBadgeSummary ubs ON ue.UserId = ubs.UserId
INNER JOIN PostHistoricalMetrics pm ON ue.UserId = pm.OwnerUserId
LEFT JOIN PostTagAnalysis pta_main ON pm.PostId = pta_main.PostId
LEFT JOIN AggregatedTagMetrics atm ON pta_main.TagName = atm.TagName
WHERE
    ue.Reputation < 500
    AND ue.LastAccessDate >= CURRENT_TIMESTAMP - INTERVAL '1 year'
    AND pm.PostTypeId = 1
    AND pm.PostScore < 10
    AND pm.ViewCount < 1000
    AND pm.EditCount < 2
    AND pm.WasClosed = 0
    AND ue.DisplayName IS NOT NULL
    AND ue.CreationDate > CURRENT_TIMESTAMP - INTERVAL '3 year'
    AND NOT EXISTS ( -- Correlated subquery for exclusion
        SELECT 1
        FROM Badges b_gold
        WHERE b_gold.UserId = ue.UserId AND b_gold.Class = 1 -- Users without gold badges
    )
ORDER BY
    Reputation DESC, TotalPostScore DESC, GoldBadges DESC, PostScore DESC
;
