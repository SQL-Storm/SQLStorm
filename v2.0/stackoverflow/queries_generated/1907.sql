-- {"query": "1907.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 4924} 

WITH UserEngagement AS (
    -- Aggregates user activity metrics from Posts and Comments, including detailed post history counts.
    -- This CTE establishes a foundational view of user activity, combining several source tables.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        -- Counts accepted answers where the user is the owner of the question AND the owner of the accepted answer.
        SUM(CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL AND p_ans.OwnerUserId = u.Id THEN 1 ELSE 0 END) AS AcceptedAnswersCount,
        SUM(COALESCE(p.ViewCount, 0)) AS TotalPostViews,
        SUM(p.Score) AS TotalPostScore,
        COUNT(DISTINCT c.Id) AS TotalComments,
        SUM(COALESCE(c.Score, 0)) AS TotalCommentScore,
        -- Determines the latest activity across posts, comments, and user's last access.
        MAX(GREATEST(p.LastActivityDate, c.CreationDate, u.LastAccessDate)) AS LastActivityDetected,
        COUNT(DISTINCT ph.Id) AS TotalPostHistoryEntries,
        AVG(COALESCE(p.AnswerCount, 0)) FILTER (WHERE p.PostTypeId = 1) AS AvgAnswersPerQuestionPosted
    FROM
        Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    -- Self-join on Posts to find the owner of the accepted answer for a question.
    LEFT JOIN Posts p_ans ON p.AcceptedAnswerId = p_ans.Id AND p.PostTypeId = 1
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
TagPerformance AS (
    -- Processes the 'Tags' string column from 'Posts' to explode tags into individual rows.
    -- This allows for per-tag analysis and aggregation later.
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount,
        LOWER(TRIM(SUBSTRING(unnest(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><')), 1, 35))) AS TagName
    FROM
        Posts p
    WHERE
        p.PostTypeId = 1 -- Only consider questions for tag analysis.
        AND p.Tags IS NOT NULL
        AND LENGTH(p.Tags) > 2 -- Exclude empty or malformed tag strings.
),
TopTagsByPost AS (
    -- Ranks tags within each post by their score, useful for identifying the 'main' tag of a post.
    SELECT
        tp.PostId,
        tp.TagName,
        tp.PostScore,
        tp.ViewCount,
        tp.AnswerCount,
        SUM(tp.PostScore) OVER (PARTITION BY tp.TagName) AS TagTotalScore, -- Global sum of score per tag.
        ROW_NUMBER() OVER (PARTITION BY tp.PostId ORDER BY tp.PostScore DESC, tp.ViewCount DESC) AS rn_tag_score
    FROM
        TagPerformance tp
),
UserBadgeSummary AS (
    -- Summarizes badge information for each user, categorizing by badge class.
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(DISTINCT b.Name) AS DistinctBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM
        Badges b
    GROUP BY
        b.UserId
),
PostLinkAnalysis AS (
    -- Analyzes linked and duplicate posts, calculating the time difference between linked posts.
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        pl.LinkTypeId,
        p1.CreationDate AS PostCreationDate,
        p2.CreationDate AS RelatedPostCreationDate,
        -- Calculates age difference in hours, useful for identifying quick duplicates or late links.
        EXTRACT(EPOCH FROM (p1.CreationDate - p2.CreationDate)) / 3600 AS HoursDifference
    FROM
        PostLinks pl
    JOIN Posts p1 ON pl.PostId = p1.Id
    JOIN Posts p2 ON pl.RelatedPostId = p2.Id
    WHERE
        pl.LinkTypeId IN (1, 3) -- 1 = Linked, 3 = Duplicate.
),
FrequentEditorStats AS (
    -- Identifies users who frequently edit posts (either their own or others'), focusing on various edit types.
    -- Includes a LAG function to find the previous edit date for a user, enabling interval analysis.
    SELECT
        ph.UserId,
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate AS EditDate,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.PostHistoryTypeId ORDER BY ph.CreationDate DESC) AS rn_edit_type,
        LAG(ph.CreationDate) OVER (PARTITION BY ph.UserId ORDER BY ph.CreationDate) AS PrevEditDate
    FROM
        PostHistory ph
    WHERE
        ph.PostHistoryTypeId IN (4, 5, 6, 8, 9, 24) -- Specific PostHistoryTypes for various edits/rollbacks/suggestions.
),
ModerationActionSummary AS (
    -- Summarizes moderation actions (close, reopen, delete, protect) on posts from PostHistory.
    SELECT
        ph.PostId,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseVotes,
        SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenVotes,
        SUM(CASE WHEN ph.PostHistoryTypeId = 12 THEN 1 ELSE 0 END) AS DeleteVotes,
        SUM(CASE WHEN ph.PostHistoryTypeId = 19 THEN 1 ELSE 0 END) AS ProtectVotes,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate ELSE NULL END) AS LastClosedDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 12 THEN ph.CreationDate ELSE NULL END) AS LastDeletedDate
    FROM
        PostHistory ph
    WHERE
        ph.PostHistoryTypeId IN (10, 11, 12, 13, 19, 20) -- Relevant moderation action types.
    GROUP BY
        ph.PostId
),
UserQuestionPerformance AS (
    -- Detailed performance metrics for a user's questions, including correlated subqueries for specific counts and dates.
    SELECT
        ue.UserId,
        ue.DisplayName,
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate AS QuestionCreationDate,
        p.Score AS QuestionScore,
        p.ViewCount AS QuestionViewCount,
        p.AnswerCount,
        -- Correlated subquery: Counts comments made after the first week of the question's creation.
        (SELECT COUNT(c.Id) FROM Comments c WHERE c.PostId = p.Id AND c.CreationDate > p.CreationDate + INTERVAL '7 days') AS CommentsAfterFirstWeek,
        -- Correlated subquery: Finds the last date a question's body was edited.
        (SELECT MAX(ph_sub.CreationDate) FROM PostHistory ph_sub WHERE ph_sub.PostId = p.Id AND ph_sub.PostHistoryTypeId = 5) AS LastBodyEditDate,
        COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
        -- Ranks questions by score and view count within each user's portfolio.
        RANK() OVER (PARTITION BY ue.UserId ORDER BY p.Score DESC, p.ViewCount DESC) AS RankByScoreAndViews,
        -- Retrieves the view count of the user's next question chronologically.
        LEAD(p.ViewCount, 1, 0) OVER (PARTITION BY ue.UserId ORDER BY p.CreationDate) AS NextQuestionViewCount
    FROM
        UserEngagement ue
    JOIN Posts p ON ue.UserId = p.OwnerUserId
    WHERE
        p.PostTypeId = 1
),
TagStatsGlobal AS (
    -- Global statistics for tags, including a correlated subquery for average view count across all posts with that tag.
    SELECT
        TagName,
        COUNT(DISTINCT PostId) AS TotalPostsWithTag,
        SUM(PostScore) AS TotalTagScore,
        AVG(PostScore) AS AveragePostScoreForTag,
        -- Correlated subquery: Calculates average view count for all posts containing this specific tag.
        (SELECT AVG(p_inner.ViewCount) FROM Posts p_inner WHERE p_inner.Tags ILIKE CONCAT('%<', tsg.TagName, '>%')) AS AverageViewCountForTag,
        RANK() OVER (ORDER BY SUM(PostScore) DESC) AS TagScoreRank
    FROM
        TopTagsByPost ttp
    GROUP BY
        TagName
),
HeavyUsers AS (
    -- First branch of the UNION ALL: focuses on highly engaged users based on reputation, activity, and contribution.
    SELECT
        ue.UserId,
        ue.DisplayName,
        ue.Reputation,
        ue.TotalPosts,
        ue.TotalQuestions,
        ue.TotalAnswers,
        ue.AcceptedAnswersCount,
        ue.TotalPostViews,
        ue.TotalPostScore,
        ue.TotalComments,
        ue.TotalCommentScore,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ub.DistinctBadges,
        COALESCE(ub.LastBadgeDate, '1900-01-01') AS LastBadgeAwardDate,
        ue.LastActivityDetected,
        -- Aggregates the top 5 most highly scored tags the user has contributed to globally.
        STRING_AGG(DISTINCT tsg.TagName, ', ') FILTER (WHERE tsg.TagScoreRank <= 5) AS Top5ContributedTags,
        qperf.QuestionId AS TopQuestionId,
        qperf.Title AS TopQuestionTitle,
        qperf.QuestionScore AS TopQuestionScore,
        qperf.QuestionViewCount AS TopQuestionViewCount,
        qperf.CommentsAfterFirstWeek,
        qperf.LastBodyEditDate,
        qperf.FavoriteCount,
        mas.CloseVotes,
        mas.ReopenVotes,
        mas.DeleteVotes,
        mas.ProtectVotes,
        -- Identifies the latest date of any moderation action.
        GREATEST(COALESCE(mas.LastClosedDate, '1900-01-01'), COALESCE(mas.LastDeletedDate, '1900-01-01')) AS LatestModerationActionDate,
        COUNT(DISTINCT pl.RelatedPostId) FILTER (WHERE pl.LinkTypeId = 1) AS LinkedPostCount,
        COUNT(DISTINCT pl.RelatedPostId) FILTER (WHERE pl.LinkTypeId = 3) AS DuplicatePostCount,
        AVG(pl.HoursDifference) FILTER (WHERE pl.LinkTypeId = 3 AND pl.HoursDifference > 0) AS AvgDuplicatePostAgeDiffHours,
        SUM(CASE WHEN fe.PostHistoryTypeId = 5 AND EXTRACT(DAY FROM (NOW() - fe.EditDate)) < 180 THEN 1 ELSE 0 END) AS RecentBodyEdits,
        -- Divides users into 10 tiers based on reputation and total post score.
        NTILE(10) OVER (ORDER BY ue.Reputation DESC, ue.TotalPostScore DESC) AS UserReputationTier,
        -- Scalar subquery: Calculates average bounty amount started by the user.
        (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.UserId = ue.UserId AND v.VoteTypeId = 8) AS AvgBountyStarted,
        -- Correlated subquery: Counts the number of questions owned by the user that were closed but not community-owned.
        (SELECT COUNT(DISTINCT p_closed.Id) FROM Posts p_closed WHERE p_closed.OwnerUserId = ue.UserId AND p_closed.ClosedDate IS NOT NULL AND p_closed.CommunityOwnedDate IS NULL) AS UserClosedQuestions,
        -- Complex CASE statement to categorize user contribution level based on multiple criteria.
        CASE
            WHEN ue.Reputation >= 20000 AND ub.GoldBadges >= 3 AND ue.TotalQuestions >= 50 THEN 'Veteran Top Contributor'
            WHEN ue.Reputation >= 5000 AND ub.SilverBadges >= 5 AND ue.TotalAnswers >= 30 THEN 'Established Expert'
            WHEN ue.Reputation >= 1000 AND ue.TotalPosts >= 10 THEN 'Active Participant'
            ELSE 'Casual User'
        END AS UserContributionLevel,
        -- Calculation using NULLIF to prevent division by zero.
        NULLIF(ue.TotalPostScore, 0) / NULLIF(ue.TotalQuestions + ue.TotalAnswers, 0) AS AvgScorePerContribution,
        LOWER(u.Location) AS LowercaseLocation,
        -- Boolean expression for identifying users with tech-related keywords in their 'AboutMe'.
        (u.AboutMe ILIKE '%SQL%' OR u.AboutMe ILIKE '%database%' OR u.AboutMe ILIKE '%developer%') AS IsTechUser,
        'Heavy User' AS UserCategory
    FROM
        UserEngagement ue
    LEFT JOIN UserBadgeSummary ub ON ue.UserId = ub.UserId
    LEFT JOIN UserQuestionPerformance qperf ON ue.UserId = qperf.UserId AND qperf.RankByScoreAndViews = 1
    LEFT JOIN ModerationActionSummary mas ON qperf.QuestionId = mas.PostId
    LEFT JOIN PostLinkAnalysis pl ON qperf.QuestionId = pl.PostId
    LEFT JOIN FrequentEditorStats fe ON ue.UserId = fe.UserId
    LEFT JOIN Users u ON ue.UserId = u.Id
    LEFT JOIN TagStatsGlobal tsg ON tsg.TagName IN (
        SELECT LOWER(TRIM(SUBSTRING(unnest(string_to_array(SUBSTRING(p_main.Tags, 2, LENGTH(p_main.Tags) - 2), '><')), 1, 35)))
        FROM Posts p_main WHERE p_main.Id = qperf.QuestionId AND p_main.Tags IS NOT NULL
    )
    WHERE
        ue.Reputation >= 1000
        AND ue.TotalPosts > 10
        AND ue.LastActivityDetected >= NOW() - INTERVAL '1 year'
    GROUP BY
        ue.UserId, ue.DisplayName, ue.Reputation, ue.TotalPosts, ue.TotalQuestions, ue.TotalAnswers,
        ue.AcceptedAnswersCount, ue.TotalPostViews, ue.TotalPostScore, ue.TotalComments, ue.TotalCommentScore,
        ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges, ub.DistinctBadges, ub.LastBadgeDate,
        ue.LastActivityDetected, qperf.QuestionId, qperf.Title, qperf.QuestionScore,
        qperf.QuestionViewCount, qperf.CommentsAfterFirstWeek, qperf.LastBodyEditDate,
        qperf.FavoriteCount, mas.CloseVotes, mas.ReopenVotes, mas.DeleteVotes, mas.ProtectVotes,
        mas.LastClosedDate, mas.LastDeletedDate, u.Location, u.AboutMe, ue.AvgAnswersPerQuestionPosted
    HAVING
        COUNT(DISTINCT CASE WHEN fe.PostHistoryTypeId = 5 AND EXTRACT(DAY FROM (NOW() - fe.EditDate)) < 180 THEN fe.PostId END) > 0
        OR COUNT(DISTINCT pl.RelatedPostId) FILTER (WHERE pl.LinkTypeId = 3) > 0
),
ModeratorActionTargetUsers AS (
    -- Second branch of the UNION ALL: focuses on users whose posts have been subject to significant moderation actions.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        ue.TotalPosts,
        ue.TotalQuestions,
        ue.TotalAnswers,
        ue.AcceptedAnswersCount,
        ue.TotalPostViews,
        ue.TotalPostScore,
        ue.TotalComments,
        ue.TotalCommentScore,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ub.DistinctBadges,
        COALESCE(ub.LastBadgeDate, '1900-01-01') AS LastBadgeAwardDate,
        ue.LastActivityDetected,
        STRING_AGG(DISTINCT tsg.TagName, ', ') FILTER (WHERE tsg.TagScoreRank <= 5) AS Top5ContributedTags,
        p_mod.Id AS TopQuestionId,
        p_mod.Title AS TopQuestionTitle,
        p_mod.Score AS TopQuestionScore,
        p_mod.ViewCount AS TopQuestionViewCount,
        (SELECT COUNT(c.Id) FROM Comments c WHERE c.PostId = p_mod.Id AND c.CreationDate > p_mod.CreationDate + INTERVAL '7 days') AS CommentsAfterFirstWeek,
        (SELECT MAX(ph_sub.CreationDate) FROM PostHistory ph_sub WHERE ph_sub.PostId = p_mod.Id AND ph_sub.PostHistoryTypeId = 5) AS LastBodyEditDate,
        COALESCE(p_mod.FavoriteCount, 0) AS FavoriteCount,
        mas.CloseVotes,
        mas.ReopenVotes,
        mas.DeleteVotes,
        mas.ProtectVotes,
        GREATEST(COALESCE(mas.LastClosedDate, '1900-01-01'), COALESCE(mas.LastDeletedDate, '1900-01-01')) AS LatestModerationActionDate,
        COUNT(DISTINCT pl.RelatedPostId) FILTER (WHERE pl.LinkTypeId = 1) AS LinkedPostCount,
        COUNT(DISTINCT pl.RelatedPostId) FILTER (WHERE pl.LinkTypeId = 3) AS DuplicatePostCount,
        AVG(pl.HoursDifference) FILTER (WHERE pl.LinkTypeId = 3 AND pl.HoursDifference > 0) AS AvgDuplicatePostAgeDiffHours,
        SUM(CASE WHEN fe.PostHistoryTypeId = 5 AND EXTRACT(DAY FROM (NOW() - fe.EditDate)) < 180 THEN 1 ELSE 0 END) AS RecentBodyEdits,
        NTILE(10) OVER (ORDER BY u.Reputation DESC, ue.TotalPostScore DESC) AS UserReputationTier,
        (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 8) AS AvgBountyStarted,
        (SELECT COUNT(DISTINCT p_closed.Id) FROM Posts p_closed WHERE p_closed.OwnerUserId = u.Id AND p_closed.ClosedDate IS NOT NULL AND p_closed.CommunityOwnedDate IS NULL) AS UserClosedQuestions,
        CASE
            WHEN u.Reputation >= 10000 AND mas.CloseVotes >= 5 THEN 'Moderation Target (High Rep)'
            WHEN mas.DeleteVotes >= 1 THEN 'Moderation Target (Deleted Post)'
            ELSE 'Moderation Target (General)'
        END AS UserContributionLevel,
        NULLIF(ue.TotalPostScore, 0) / NULLIF(ue.TotalQuestions + ue.TotalAnswers, 0) AS AvgScorePerContribution,
        LOWER(u.Location) AS LowercaseLocation,
        (u.AboutMe ILIKE '%moderator%' OR u.AboutMe ILIKE '%admin%' OR u.AboutMe ILIKE '%community%') AS IsTechUser,
        'Moderation Impacted' AS UserCategory
    FROM
        Users u
    LEFT JOIN UserEngagement ue ON u.Id = ue.UserId
    LEFT JOIN UserBadgeSummary ub ON u.Id = ub.UserId
    JOIN Posts p_mod ON u.Id = p_mod.OwnerUserId AND p_mod.PostTypeId = 1
    JOIN ModerationActionSummary mas ON p_mod.Id = mas.PostId
    LEFT JOIN PostLinkAnalysis pl ON p_mod.Id = pl.PostId
    LEFT JOIN FrequentEditorStats fe ON u.Id = fe.UserId
    LEFT JOIN TagStatsGlobal tsg ON tsg.TagName IN (
        SELECT LOWER(TRIM(SUBSTRING(unnest(string_to_array(SUBSTRING(p_main.Tags, 2, LENGTH(p_main.Tags) - 2), '><')), 1, 35)))
        FROM Posts p_main WHERE p_main.Id = p_mod.Id AND p_main.Tags IS NOT NULL
    )
    WHERE