-- {"query": "1405.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 4504} 

WITH UserBaseInfo AS (
    -- Collects basic user information and applies an initial filter for activity/relevance
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Views AS UserProfileViews,
        u.UpVotes AS UserGivenUpvotes,
        u.DownVotes AS UserGivenDownvotes,
        u.Location,
        u.AboutMe
    FROM Users u
    WHERE u.CreationDate >= '2008-01-01' -- Filter users created after a specific date
      AND u.Reputation > 500 -- Focus on users with a decent reputation
      AND u.LastAccessDate >= NOW() - INTERVAL '5 year' -- Active in the last 5 years
),
PostHistoryAndEditMetrics AS (
    -- Aggregates various post history details like revision counts and major edits
    SELECT
        ph.PostId,
        COUNT(DISTINCT ph.Id) AS RevisionCount,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS MajorEditCount, -- Title, Body, Tags edits
        BOOL_OR(ph.PostHistoryTypeId = 10) AS WasClosed, -- Post closed event
        BOOL_OR(ph.PostHistoryTypeId = 11) AS WasReopened, -- Post reopened event
        MAX(ph.CreationDate) AS LastHistoryDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 10, 11, 12, 13) -- Initial, Edit, Close/Reopen, Delete/Undelete history types
    GROUP BY ph.PostId
),
PostLinkMetrics AS (
    -- Aggregates data about linked and duplicate posts
    SELECT
        p.Id AS PostId,
        COUNT(pl.Id) AS LinkedPostsCount,
        SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicatePostsCount,
        MAX(pl.CreationDate) AS LastLinkDate
    FROM Posts p
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId OR p.Id = pl.RelatedPostId -- Join on both sides to catch all links
    GROUP BY p.Id
),
CommentAndVoteMetrics AS (
    -- Aggregates comment and vote details for each post
    SELECT
        p_inner.Id AS PostId,
        COUNT(c.Id) AS TotalComments,
        SUM(c.Score) AS TotalCommentScore,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS PostUpvotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS PostDownvotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS PostAcceptedVotesOnAnswer,
        SUM(CASE WHEN v.VoteTypeId = 5 AND v.UserId IS NOT NULL THEN 1 ELSE 0 END) AS PostFavoriteVotes -- Favorite votes by users
    FROM Posts p_inner
    LEFT JOIN Comments c ON p_inner.Id = c.PostId
    LEFT JOIN Votes v ON p_inner.Id = v.PostId
    GROUP BY p_inner.Id
),
PostAggregatesCombined AS (
    -- Combines posts based on two criteria using UNION ALL to demonstrate set operators
    -- This helps identify posts that are either very popular (high views) or highly regarded (high score)
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.AcceptedAnswerId,
        p.FavoriteCount AS PostBookmarkCount, -- This is the post's favorite count, not individual user favorites
        p.LastActivityDate,
        p.Title,
        p.Tags,
        COALESCE(phem.RevisionCount, 0) AS RevisionCount,
        COALESCE(phem.MajorEditCount, 0) AS MajorEditCount,
        COALESCE(phem.WasClosed, FALSE) AS WasClosed,
        COALESCE(phem.WasReopened, FALSE) AS WasReopened,
        COALESCE(phem.LastHistoryDate, p.CreationDate) AS LastPostModificationDate,
        COALESCE(plm.LinkedPostsCount, 0) AS LinkedPostsCount,
        COALESCE(plm.DuplicatePostsCount, 0) AS DuplicatePostsCount,
        COALESCE(plm.LastLinkDate, p.CreationDate) AS LastLinkChangeDate,
        COALESCE(cvm.TotalComments, 0) AS TotalComments,
        COALESCE(cvm.TotalCommentScore, 0) AS TotalCommentScore,
        COALESCE(cvm.PostUpvotesReceived, 0) AS PostUpvotesReceived,
        COALESCE(cvm.PostDownvotesReceived, 0) AS PostDownvotesReceived,
        COALESCE(cvm.PostAcceptedVotesOnAnswer, 0) AS PostAcceptedVotesOnAnswer,
        COALESCE(cvm.PostFavoriteVotes, 0) AS PostFavoriteVotesReceived,
        'HighViews' AS PostCategory -- Label for the first branch of the UNION ALL
    FROM Posts p
    LEFT JOIN PostHistoryAndEditMetrics phem ON p.Id = phem.PostId
    LEFT JOIN PostLinkMetrics plm ON p.Id = plm.PostId
    LEFT JOIN CommentAndVoteMetrics cvm ON p.Id = cvm.PostId
    WHERE p.PostTypeId IN (1, 2) -- Only consider Questions and Answers
      AND p.CreationDate >= '2008-01-01'
      AND p.ViewCount > 50000 -- Significant view count
      AND p.LastActivityDate >= NOW() - INTERVAL '3 year'

    UNION ALL

    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.AcceptedAnswerId,
        p.FavoriteCount AS PostBookmarkCount,
        p.LastActivityDate,
        p.Title,
        p.Tags,
        COALESCE(phem.RevisionCount, 0) AS RevisionCount,
        COALESCE(phem.MajorEditCount, 0) AS MajorEditCount,
        COALESCE(phem.WasClosed, FALSE) AS WasClosed,
        COALESCE(phem.WasReopened, FALSE) AS WasReopened,
        COALESCE(phem.LastHistoryDate, p.CreationDate) AS LastPostModificationDate,
        COALESCE(plm.LinkedPostsCount, 0) AS LinkedPostsCount,
        COALESCE(plm.DuplicatePostsCount, 0) AS DuplicatePostsCount,
        COALESCE(plm.LastLinkDate, p.CreationDate) AS LastLinkChangeDate,
        COALESCE(cvm.TotalComments, 0) AS TotalComments,
        COALESCE(cvm.TotalCommentScore, 0) AS TotalCommentScore,
        COALESCE(cvm.PostUpvotesReceived, 0) AS PostUpvotesReceived,
        COALESCE(cvm.PostDownvotesReceived, 0) AS PostDownvotesReceived,
        COALESCE(cvm.PostAcceptedVotesOnAnswer, 0) AS PostAcceptedVotesOnAnswer,
        COALESCE(cvm.PostFavoriteVotes, 0) AS PostFavoriteVotesReceived,
        'HighScore' AS PostCategory -- Label for the second branch of the UNION ALL
    FROM Posts p
    LEFT JOIN PostHistoryAndEditMetrics phem ON p.Id = phem.PostId
    LEFT JOIN PostLinkMetrics plm ON p.Id = plm.PostId
    LEFT JOIN CommentAndVoteMetrics cvm ON p.Id = cvm.PostId
    WHERE p.PostTypeId IN (1, 2)
      AND p.CreationDate >= '2008-01-01'
      AND p.Score > 1000 -- Significant score
      AND p.LastActivityDate >= NOW() - INTERVAL '3 year'
      AND NOT (p.ViewCount > 50000) -- Exclude posts already covered by the 'HighViews' branch, makes UNION effectively UNION DISTINCT
),
UserPostPerformance AS (
    -- Aggregates all post-related metrics per user from the combined post data
    SELECT
        pac.OwnerUserId AS UserId,
        COUNT(pac.PostId) AS UserTotalPosts,
        SUM(CASE WHEN pac.PostTypeId = 1 THEN 1 ELSE 0 END) AS UserTotalQuestions,
        SUM(CASE WHEN pac.PostTypeId = 2 THEN 1 ELSE 0 END) AS UserTotalAnswers,
        SUM(pac.PostScore) AS UserTotalPostScore,
        SUM(pac.PostViewCount) AS UserTotalPostViews,
        SUM(pac.PostBookmarkCount) AS UserTotalBookmarkCount,
        SUM(pac.RevisionCount) AS UserTotalRevisions,
        SUM(pac.MajorEditCount) AS UserTotalMajorEdits,
        SUM(CASE WHEN pac.WasClosed THEN 1 ELSE 0 END) AS UserPostsClosedCount,
        SUM(CASE WHEN pac.WasReopened THEN 1 ELSE 0 END) AS UserPostsReopenedCount,
        SUM(pac.LinkedPostsCount) AS UserTotalLinkedPosts,
        SUM(pac.DuplicatePostsCount) AS UserTotalDuplicatePosts,
        SUM(pac.TotalComments) AS UserTotalComments,
        SUM(pac.TotalCommentScore) AS UserTotalCommentScore,
        SUM(pac.PostUpvotesReceived) AS UserTotalUpvotes,
        SUM(pac.PostDownvotesReceived) AS UserTotalDownvotes,
        SUM(pac.PostAcceptedVotesOnAnswer) AS UserTotalAcceptedAnswers,
        SUM(pac.PostFavoriteVotesReceived) AS UserTotalFavoriteVotesFromOthers,
        MAX(pac.LastActivityDate) AS LastPostActivityByUser,
        ARRAY_AGG(DISTINCT pac.PostCategory ORDER BY pac.PostCategory) AS PostCategoriesContributedTo -- Aggregating categories from UNION ALL
    FROM PostAggregatesCombined pac
    GROUP BY pac.OwnerUserId
),
UserBadgeStats AS (
    -- Summarizes badge achievements per user
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        ARRAY_AGG(DISTINCT b.Name ORDER BY b.Name LIMIT 5) AS TopBadgeNames -- List top 5 unique badge names
    FROM Badges b
    GROUP BY b.UserId
),
UserComprehensiveStats AS (
    -- Combines all user-related statistics into a single comprehensive view
    SELECT
        ubi.UserId,
        ubi.DisplayName,
        ubi.Reputation,
        ubi.UserCreationDate,
        ubi.LastAccessDate,
        ubi.UserProfileViews,
        ubi.UserGivenUpvotes,
        ubi.UserGivenDownvotes,
        ubi.Location,
        ubi.AboutMe,
        upp.UserTotalPosts,
        upp.UserTotalQuestions,
        upp.UserTotalAnswers,
        upp.UserTotalPostScore,
        upp.UserTotalPostViews,
        upp.UserTotalBookmarkCount,
        upp.UserTotalRevisions,
        upp.UserTotalMajorEdits,
        upp.UserPostsClosedCount,
        upp.UserPostsReopenedCount,
        upp.UserTotalLinkedPosts,
        upp.UserTotalDuplicatePosts,
        upp.UserTotalComments,
        upp.UserTotalCommentScore,
        upp.UserTotalUpvotes,
        upp.UserTotalDownvotes,
        upp.UserTotalAcceptedAnswers,
        upp.UserTotalFavoriteVotesFromOthers,
        upp.LastPostActivityByUser,
        upp.PostCategoriesContributedTo,
        COALESCE(ubs.TotalBadges, 0) AS TotalBadges,
        COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
        COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
        COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
        ubs.TopBadgeNames
    FROM UserBaseInfo ubi
    INNER JOIN UserPostPerformance upp ON ubi.UserId = upp.UserId -- Ensure we only analyze users who have contributed posts
    LEFT JOIN UserBadgeStats ubs ON ubi.UserId = ubs.UserId
),
RankedUsers AS (
    -- Applies window functions and derived metrics to the comprehensive user stats
    SELECT
        ucs.*,
        (CAST(ucs.UserTotalUpvotes AS NUMERIC) - CAST(ucs.UserTotalDownvotes AS NUMERIC)) AS NetReceivedVotes,
        CAST(ucs.UserTotalPostScore AS NUMERIC) / NULLIF(ucs.UserTotalPosts, 0) AS AvgScorePerUserPost,
        ucs.UserTotalPosts + ucs.UserTotalComments + ucs.UserTotalMajorEdits AS UserActivityScore,
        DENSE_RANK() OVER (ORDER BY ucs.Reputation DESC, ucs.UserId) AS ReputationRank, -- Ranking by reputation
        NTILE(10) OVER (ORDER BY ucs.UserTotalUpvotes DESC) AS UpvoteDecile, -- Decile ranking by total upvotes received
        AVG(ucs.UserProfileViews) OVER (PARTITION BY ucs.Location) AS AvgProfileViewsInLocation, -- Average profile views for users in the same location
        SUM(ucs.UserTotalRevisions) OVER (PARTITION BY EXTRACT(YEAR FROM ucs.UserCreationDate)) AS TotalRevisionsByCreationYear, -- Total revisions by users created in the same year
        LAG(ucs.Reputation, 1, 0) OVER (ORDER BY ucs.Reputation DESC, ucs.UserId) AS PrevRankedUserReputation, -- Reputation of the user ranked immediately before
        LEAD(ucs.Reputation, 1, 0) OVER (ORDER BY ucs.Reputation DESC, ucs.UserId) AS NextRankedUserReputation -- Reputation of the user ranked immediately after
    FROM UserComprehensiveStats ucs
    WHERE ucs.UserTotalPosts > 100 -- Filter for users with a significant number of posts
      AND ucs.UserTotalUpvotes > 2000 -- Filter for users who received many upvotes
      AND ucs.NetReceivedVotes IS NOT NULL -- Ensure net votes are calculable
      AND ucs.AboutMe IS NOT NULL AND LENGTH(TRIM(ucs.AboutMe)) > 50 -- Users with substantial "About Me" sections
)
-- Final selection and presentation of influential users
SELECT
    ru.UserId,
    ru.DisplayName,
    ru.Reputation,
    ru.ReputationRank,
    ru.NetReceivedVotes,
    ru.AvgScorePerUserPost,
    ru.TotalBadges,
    ru.GoldBadges,
    ru.TopBadgeNames,
    ru.UserTotalQuestions,
    ru.UserTotalAnswers,
    ru.UserTotalAcceptedAnswers,
    ru.UserPostsClosedCount,
    ru.UserTotalMajorEdits,
    ru.PostCategoriesContributedTo,
    -- Correlated subquery: Determine the most frequent tag used by a user for their questions
    (
        SELECT tg.TagName
        FROM PostAggregatesCombined pac_inner
        CROSS JOIN LATERAL UNNEST(string_to_array(SUBSTRING(pac_inner.Tags FROM 2 FOR LENGTH(pac_inner.Tags)-2), '><')) AS tag_name_unnest
        JOIN Tags tg ON LOWER(tg.TagName) = LOWER(tag_name_unnest)
        WHERE pac_inner.OwnerUserId = ru.UserId
          AND pac_inner.PostTypeId = 1 -- Only questions
          AND pac_inner.Tags IS NOT NULL
          AND pac_inner.PostCreationDate BETWEEN ru.UserCreationDate AND ru.LastPostActivityByUser + INTERVAL '6 months' -- Tag activity window
        GROUP BY tg.TagName
        ORDER BY COUNT(*) DESC, tg.TagName ASC
        LIMIT 1
    ) AS MostFrequentQuestionTag,
    -- Correlated subquery: Calculate the average score of posts by this user that have been linked more than once
    COALESCE((
        SELECT AVG(pac_linked.PostScore)
        FROM PostAggregatesCombined pac_linked
        WHERE pac_linked.OwnerUserId = ru.UserId
          AND pac_linked.LinkedPostsCount > 1
          AND pac_linked.PostScore > 0 -- Only positive scores
          AND pac_linked.PostCreationDate > NOW() - INTERVAL '4 years' -- Recent highly linked posts
    ), 0.0) AS AvgScoreOfHighlyLinkedPosts,
    -- Complex string expression demonstrating multiple string functions and NULL logic
    CONCAT(
        UPPER(SUBSTRING(ru.DisplayName FROM 1 FOR 1)), -- Capitalize first letter
        LOWER(SUBSTRING(ru.DisplayName FROM 2)), -- Lowercase rest of display name
        ' (Rep:',
        LPAD(ru.Reputation::TEXT, 7, '0'), -- Pad reputation with leading zeros
        ', Views:',
        LPAD(ru.UserProfileViews::TEXT, 7, '0'),
        ', Loc:',
        COALESCE(REPLACE(ru.Location, ' ', '_'), 'UNKNOWN_LOCATION'), -- Replace spaces in location, handle NULL
        ', Created:',
        TO_CHAR(ru.UserCreationDate, 'YYYY-MM-DD'), -- Format creation date
        ') Post Score Diff: ',
        (ru.UserTotalPostScore - (SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = ru.UserId AND p.PostTypeId = 1))::TEXT -- Subquery for avg score diff
    ) AS UserSummaryComplexString,
    -- Complicated predicate/expression/calculation with CASE and NULL logic to categorize user engagement
    CASE
        WHEN ru.NetReceivedVotes > 10000 AND ru.GoldBadges >= 5 AND ru.UserTotalMajorEdits > 100 THEN 'Elite Contributor (Gold Tier)'
        WHEN ru.NetReceivedVotes > 5000 AND ru.UserTotalAcceptedAnswers >= 20 AND ru.TotalBadges >= 100 THEN 'Valued Expert (Silver Tier)'
        WHEN ru.UserTotalQuestions > 100 AND ru.UserTotalUpvotes > 1000 AND ru.UserTotalComments > 200 THEN 'Active Community Member (Bronze Tier)'
        WHEN ru.UserProfileViews IS NULL OR ru.UserProfileViews < 100 THEN 'Shadow Member (Low Visibility)'
        ELSE 'General Participant (Engaged)'
    END AS UserEngagementSegment,
    -- Calculation: Average daily activity score normalized by user's existence duration
    CAST(ru.UserActivityScore AS NUMERIC) / NULLIF(EXTRACT(EPOCH FROM AGE(ru.LastAccessDate, ru.UserCreationDate)) / 86400, 0) AS AvgDailyActivityScore,
    ru.PrevRankedUserReputation,
    ru.NextRankedUserReputation,