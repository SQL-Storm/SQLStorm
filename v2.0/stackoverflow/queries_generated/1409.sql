-- {"query": "1409.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3066} 

WITH UserEngagement AS (
    -- CTE 1: Aggregates user-level engagement statistics
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Reputation,
        u.UpVotes AS TotalUpvotesGivenBySelf,
        u.DownVotes AS TotalDownvotesGivenBySelf,
        COUNT(DISTINCT p_owned.Id) AS TotalPostsOwned,
        COUNT(DISTINCT c_made.Id) AS TotalCommentsMade,
        SUM(CASE WHEN v_given.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesGivenToOthers,
        SUM(p_owned.Score) AS TotalPostScoreReceived, -- Sum of scores of posts owned by user
        AVG(CAST(p_owned.Score AS NUMERIC)) FILTER (WHERE p_owned.PostTypeId IN (1, 2)) AS AvgOwnedPostScore,
        EXTRACT(DAY FROM (u.LastAccessDate - u.CreationDate)) AS DaysActive,
        MAX(CASE WHEN b_gold.Class = 1 THEN 1 ELSE 0 END) AS HasGoldBadge,
        COUNT(DISTINCT ph_user.Id) AS TotalPostHistoryEventsByThisUser
    FROM Users u
    LEFT JOIN Posts p_owned ON u.Id = p_owned.OwnerUserId
    LEFT JOIN Comments c_made ON u.Id = c_made.UserId
    LEFT JOIN Votes v_given ON u.Id = v_given.UserId
    LEFT JOIN Badges b_gold ON u.Id = b_gold.UserId
    LEFT JOIN PostHistory ph_user ON u.Id = ph_user.UserId
    GROUP BY u.Id, u.DisplayName, u.CreationDate, u.LastAccessDate, u.Reputation, u.UpVotes, u.DownVotes
),
PostComplexStats AS (
    -- CTE 2: Aggregates post-level complex statistics, focusing on Questions (PostTypeId = 1)
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.CommunityOwnedDate,
        COALESCE(p.OwnerUserId, -1) AS OwnerId, -- Handle community user or deleted owner
        (
            SELECT STRING_AGG(LOWER(tag_value), ';')
            FROM (
                SELECT unnest(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) AS tag_value
                WHERE p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2
                ORDER BY LENGTH(tag_value) DESC -- Order tags for consistent aggregation
                LIMIT 5 -- Limit to top 5 longest tags
            ) AS unnested_tags
        ) AS Top5TagsString,
        COUNT(DISTINCT pl_link.Id) AS TotalRelatedLinks,
        AVG(LENGTH(ans.Body)) FILTER (WHERE ans.Id IS NOT NULL AND ans.Body IS NOT NULL) AS AvgAnswerBodyLength,
        (CAST(SUM(CASE WHEN pv.VoteTypeId = 2 THEN 1 ELSE 0 END) AS NUMERIC) /
         NULLIF(SUM(CASE WHEN pv.VoteTypeId = 3 THEN 1 ELSE 0 END), 0)) AS QuestionUpvoteDownvoteRatio,
        MAX(CASE WHEN ph_close.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS WasClosed,
        MAX(CASE WHEN ph_reopen.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS WasReopened,
        MAX(CASE WHEN ph_delete.PostHistoryTypeId = 12 THEN 1 ELSE 0 END) AS WasDeleted
    FROM Posts p
    LEFT JOIN Posts ans ON p.Id = ans.ParentId AND ans.PostTypeId = 2 -- Answers to this question
    LEFT JOIN PostLinks pl_link ON p.Id = pl_link.PostId OR p.Id = pl_link.RelatedPostId
    LEFT JOIN Votes pv ON p.Id = pv.PostId AND pv.VoteTypeId IN (2, 3) -- Up/Down votes on the post itself
    LEFT JOIN PostHistory ph_close ON p.Id = ph_close.PostId AND ph_close.PostHistoryTypeId = 10
    LEFT JOIN PostHistory ph_reopen ON p.Id = ph_reopen.PostId AND ph_reopen.PostHistoryTypeId = 11
    LEFT JOIN PostHistory ph_delete ON p.Id = ph_delete.PostId AND ph_delete.PostHistoryTypeId = 12
    WHERE p.PostTypeId = 1 -- Focus on Questions
    GROUP BY p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount,
             p.ClosedDate, p.CommunityOwnedDate, p.OwnerUserId, p.Tags
),
EditorActivityTrends AS (
    -- CTE 3: Tracks editing activity and time differences between edits for each post
    SELECT
        ph.PostId,
        ph.UserId AS EditorUserId,
        ph.CreationDate AS EditDate,
        ph.PostHistoryTypeId,
        LAG(ph.CreationDate, 1, ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PreviousEditDate,
        EXTRACT(HOUR FROM (ph.CreationDate - LAG(ph.CreationDate, 1, ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate))) AS HoursSinceLastEdit,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS EditSequence
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6, 8, 9, 24) -- Edit Title, Body, Tags, Rollback Body, Rollback Tags, Suggested Edit Applied
)
SELECT
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.TotalPostsOwned,
    ue.AvgOwnedPostScore,
    pcs.PostId,
    pcs.PostScore,
    pcs.ViewCount,
    pcs.AnswerCount,
    pcs.Top5TagsString,
    pcs.AvgAnswerBodyLength,
    pcs.QuestionUpvoteDownvoteRatio,
    COALESCE(ph_latest_edit.EditDate, pcs.PostCreationDate) AS LastRecordedActivityOnPost,
    COALESCE(ph_first_editor.EditorUserId, ue.UserId) AS OriginalPostEditorId,
    ph_first_editor.EditDate AS FirstEditDate,
    MAX(eat.HoursSinceLastEdit) OVER (PARTITION BY ue.UserId, pcs.PostId) AS MaxHoursBetweenPostEdits,
    SUM(CASE WHEN eat.EditSequence > 1 THEN 1 ELSE 0 END) OVER (PARTITION BY ue.UserId, pcs.PostId) AS TotalSubsequentEditsOnPost,
    DENSE_RANK() OVER (ORDER BY ue.TotalPostsOwned DESC, ue.AvgOwnedPostScore DESC, ue.Reputation DESC) AS UserEngagementRank,
    (
        SELECT COUNT(DISTINCT b_sub.Id)
        FROM Badges b_sub
        WHERE b_sub.UserId = ue.UserId AND b_sub.Date >= ue.UserCreationDate AND b_sub.TagBased = FALSE
    ) AS TotalNamedBadgesForUser,
    (
        SELECT SUM(LENGTH(c_sub.Text))
        FROM Comments c_sub
        WHERE c_sub.PostId = pcs.PostId
          AND c_sub.CreationDate BETWEEN pcs.PostCreationDate + INTERVAL '1 hour' AND pcs.PostCreationDate + INTERVAL '7 day'
          AND c_sub.Text IS NOT NULL
    ) AS TotalCommentCharsInFirstWeek,
    CASE
        WHEN pcs.WasClosed = 1 AND pcs.WasReopened = 0 THEN 'Closed_NeverReopened'
        WHEN pcs.WasClosed = 1 AND pcs.WasReopened = 1 THEN 'Closed_ThenReopened'
        WHEN pcs.WasDeleted = 1 THEN 'Deleted'
        ELSE 'Active_Open'
    END AS PostLifecycleStatus,
    CASE
        WHEN ue.HasGoldBadge = 1 AND ue.TotalUpvotesGivenToOthers > 500 AND ue.TotalPostsOwned > 20 THEN 'High_Impact_Veteran'
        WHEN ue.DaysActive > 730 AND ue.Reputation > 10000 THEN 'Long_Term_Influencer'
        WHEN ue.TotalCommentsMade > 100 AND ue.TotalPostsOwned = 0 THEN 'Commenter_Specialist'
        ELSE 'General_Contributor'
    END AS UserContributionSegment,
    (COALESCE(ue.TotalUpvotesGivenToOthers, 0) + COALESCE(ue.TotalPostScoreReceived, 0)) / NULLIF(ue.TotalCommentsMade + ue.TotalPostsOwned + 1, 0) AS UserActivityWeight,
    EXISTS (
        SELECT 1
        FROM PostLinks pl_duplicate_check
        WHERE pl_duplicate_check.PostId = pcs.PostId AND pl_duplicate_check.LinkTypeId = 3
    ) AS HasDuplicateLinks,
    LOWER(SUBSTRING(ue.DisplayName, 1, 3)) ||
    UPPER(SUBSTRING(REPLACE(COALESCE(ue.DisplayName, 'UNKNOWN'), ' ', ''),
                    LENGTH(REPLACE(COALESCE(ue.DisplayName, 'UNKNOWN'), ' ', '')) - 2, 3)) AS DisplayNameHashSuffix,
    COALESCE(pcs.FavoriteCount, 0) + (pcs.PostScore * 0.75) + (pcs.ViewCount * 0.01) AS WeightedPopularityScore,
    EXTRACT(DOW FROM pcs.PostCreationDate) AS DayOfWeekOfCreation, -- Sunday = 0, Saturday = 6
    (SELECT COUNT(DISTINCT ph_mig.PostId) FROM PostHistory ph_mig WHERE ph_mig.UserId = ue.UserId AND ph_mig.PostHistoryTypeId = 35) AS MigratedPostsInitiatedByOwner
FROM UserEngagement ue
INNER JOIN PostComplexStats pcs ON ue.UserId = pcs.OwnerId
LEFT JOIN EditorActivityTrends eat ON pcs.PostId = eat.PostId AND eat.EditSequence > 1 -- Only considering subsequent edits for trend analysis
LEFT JOIN EditorActivityTrends ph_latest_edit ON pcs.PostId = ph_latest_edit.PostId AND ph_latest_edit.EditSequence = (SELECT MAX(eat_max.EditSequence) FROM EditorActivityTrends eat_max WHERE eat_max.PostId = pcs.PostId)
LEFT JOIN EditorActivityTrends ph_first_editor ON pcs.PostId = ph_first_editor.PostId AND ph_first_editor.EditSequence = 1
WHERE
    ue.TotalPostsOwned > 3
    AND pcs.ViewCount > 500
    AND (pcs.PostScore > 50 OR pcs.FavoriteCount IS NOT NULL AND pcs.FavoriteCount > 5)
    AND ue.DaysActive IS NOT NULL AND ue.DaysActive > 90
    AND (
            (pcs.AvgAnswerBodyLength IS NOT NULL AND pcs.AvgAnswerBodyLength > 200)
            OR
            (pcs.QuestionUpvoteDownvoteRatio IS NOT NULL AND pcs.QuestionUpvoteDownvoteRatio > 10)
        )
    AND NOT EXISTS (
        SELECT 1
        FROM Comments c_no_user_check
        WHERE c_no_user_check.PostId = pcs.PostId
          AND c_no_user_check.UserId IS NULL -- Comments by deleted/anonymous users
          AND c_no_user_check.CreationDate > (pcs.PostCreationDate - INTERVAL '1 month') -- in the last month relative to post creation
    )
    AND (pcs.Top5TagsString LIKE '%sql%' OR pcs.Top5TagsString LIKE '%database%' OR pcs.Top5TagsString LIKE '%performance%')
GROUP BY
    ue.UserId, ue.DisplayName, ue.Reputation, ue.TotalPostsOwned, ue.AvgOwnedPostScore, ue.TotalUpvotesGivenToOthers,
    ue.TotalPostScoreReceived, ue.TotalCommentsMade, ue.HasGoldBadge, ue.DaysActive, ue.UserCreationDate,
    pcs.PostId, pcs.PostScore, pcs.ViewCount, pcs.AnswerCount, pcs.Top5TagsString, pcs.AvgAnswerBodyLength,
    pcs.QuestionUpvoteDownvoteRatio, pcs.PostCreationDate, pcs.FavoriteCount, pcs.WasClosed, pcs.WasReopened, pcs.WasDeleted,
    ph_latest_edit.EditDate, ph_first_editor.EditorUserId, ph_first_editor.EditDate
HAVING
    COUNT(DISTINCT eat.EditorUserId) > 0 -- Ensure the post has at least one recorded subsequent edit (after the initial post)
    AND MAX(ue.Reputation) > 1000 -- Filter for users with significant reputation
ORDER BY
    UserEngagementRank ASC, WeightedPopularityScore DESC, LastRecordedActivityOnPost DESC
LIMIT 500;
