-- {"query": "1909.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3281} 

WITH UserPostAggregates AS (
    -- Calculate user-level aggregates for posts
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        SUM(p.Score) AS TotalPostScoreOwned,
        AVG(p.Score) AS AveragePostScoreOwned,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsAsked,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersPosted,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL AND p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalAcceptedAnswersOnQuestionsOwned,
        SUM(CASE WHEN p.ParentId IS NOT NULL AND ap.AcceptedAnswerId = p.Id THEN 1 ELSE 0 END) AS TotalAnswersAcceptedByOthers
    FROM Posts AS p
    LEFT JOIN Posts AS ap ON p.ParentId = ap.Id -- Join to parent for accepted answer check
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserCommentMetrics AS (
    -- Calculate user-level aggregates for comments they made
    SELECT
        c.UserId,
        COUNT(c.Id) AS TotalCommentsMade,
        SUM(c.Score) AS TotalCommentScoreMade
    FROM Comments AS c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
PostHistoricalEvents AS (
    -- Identify specific historical events for posts and aggregate them
    SELECT
        ph.PostId,
        COUNT(ph.Id) AS TotalHistoryEvents,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) THEN ph.Id END) AS EditCount, -- Title/Body/Tags edits/rollbacks
        COUNT(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Id END) AS CloseCount,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.Id END) AS ReopenCount,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 12 THEN ph.Id END) AS DeleteCount,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (35, 36) THEN ph.Id END) AS MigrationCount, -- Migrated Away/Here
        MAX(ph.CreationDate) AS LastHistoryEventDate,
        -- Extract CloseReasonId if available for the last close event
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment ELSE NULL END) AS LastCloseReasonId
    FROM PostHistory AS ph
    GROUP BY ph.PostId
),
PostVoteAggregates AS (
    -- Calculate vote aggregates for posts
    SELECT
        v.PostId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpVoteCount,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownVoteCount,
        COUNT(CASE WHEN v.VoteTypeId = 5 THEN v.Id END) AS FavoriteCountTotal, -- Note: Favorite votes are user-specific and historical
        SUM(CASE WHEN v.VoteTypeId IN (2, 3, 5) THEN 1 ELSE 0 END) AS TotalVotesReceived,
        COUNT(DISTINCT v.UserId) AS UniqueVoters
    FROM Votes AS v
    GROUP BY v.PostId
),
UserBadgeSummary AS (
    -- Summarize user badges
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges AS b
    GROUP BY b.UserId
),
UserPostDetailWithWindows AS (
    -- Combine post details with historical events and vote aggregates, and apply window functions
    SELECT
        p.Id AS PostId,
        p.OwnerUserId AS UserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.PostTypeId,
        p.Tags,
        p.Title,
        p.Body,
        p.ClosedDate,
        COALESCE(phe.CloseCount, 0) AS CloseCount,
        phe.LastCloseReasonId,
        COALESCE(phe.LastHistoryEventDate, p.LastActivityDate) AS ActualLastActivityDate, -- Use history if available, else post activity
        COALESCE(pva.UpVoteCount, 0) AS UpVoteCount,
        COALESCE(pva.DownVoteCount, 0) AS DownVoteCount,
        COALESCE(pva.FavoriteCountTotal, 0) AS FavoriteCountTotal,
        -- Window functions: running aggregates for user's posts
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS RunningAvgPostScoreUser,
        SUM(COALESCE(p.ViewCount, 0)) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS RunningTotalPostViewsUser,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostSequenceDesc
    FROM Posts AS p
    LEFT JOIN PostHistoricalEvents AS phe ON p.Id = phe.PostId
    LEFT JOIN PostVoteAggregates AS pva ON p.Id = pva.PostId
    WHERE p.OwnerUserId IS NOT NULL
),
UserEngagementRank AS (
    -- Combine user aggregates and rank them based on a composite score
    SELECT
        u.Id AS UserId,
        u.Reputation,
        upa.TotalPostsOwned,
        upa.TotalPostScoreOwned,
        ucm.TotalCommentsMade,
        ubs.TotalBadges,
        -- Calculate a composite engagement score with NULL handling
        (u.Reputation * 0.5 + COALESCE(upa.TotalPostScoreOwned, 0) * 0.3 + COALESCE(ucm.TotalCommentsMade, 0) * 0.2 + COALESCE(ubs.TotalBadges, 0) * 0.1) AS EngagementScore,
        RANK() OVER (ORDER BY (u.Reputation * 0.5 + COALESCE(upa.TotalPostScoreOwned, 0) * 0.3 + COALESCE(ucm.TotalCommentsMade, 0) * 0.2) DESC) AS OverallEngagementRank
    FROM Users AS u
    LEFT JOIN UserPostAggregates AS upa ON u.Id = upa.UserId
    LEFT JOIN UserCommentMetrics AS ucm ON u.Id = ucm.UserId
    LEFT JOIN UserBadgeSummary AS ubs ON u.Id = ubs.UserId
    WHERE u.Reputation > 0 -- Filter out users with 0 reputation (often deleted or system users)
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate AS UserLastAccessDate,
    COALESCE(u.Location, 'Unknown') AS UserLocation,
    NULLIF(u.WebsiteUrl, '') AS UserWebsite,
    eer.EngagementScore,
    eer.OverallEngagementRank,
    eer.TotalBadges,
    eer.GoldBadges,
    eer.SilverBadges,
    eer.BronzeBadges,
    (EXTRACT(EPOCH FROM (u.LastAccessDate - u.CreationDate)) / 86400) AS DaysActive, -- Days between creation and last access
    -- Correlated subquery: find the highest scoring answer *written by this user* that was accepted for *any question*
    (
        SELECT p_ans.Title
        FROM Posts AS p_ans
        WHERE p_ans.PostTypeId = 2 -- Is an answer
          AND p_ans.OwnerUserId = u.Id
          AND EXISTS (SELECT 1 FROM Posts AS q_parent WHERE q_parent.Id = p_ans.ParentId AND q_parent.AcceptedAnswerId = p_ans.Id) -- Its parent question accepted this answer
        ORDER BY p_ans.Score DESC, p_ans.CreationDate DESC
        LIMIT 1
    ) AS TopAcceptedAnswerTitleByMe,
    -- Another correlated subquery: check if user has ever had a question closed due to being a duplicate
    (
        SELECT
            MAX(CASE WHEN ph.PostHistoryTypeId = 10 AND ph.Comment = '101' THEN 'True' ELSE 'False' END)
        FROM PostHistory AS ph
        JOIN Posts AS p_hist ON ph.PostId = p_hist.Id
        WHERE p_hist.OwnerUserId = u.Id AND p_hist.PostTypeId = 1 -- Only look at questions owned by this user
    ) AS HasDuplicateClosedQuestion,
    COUNT(DISTINCT updw.PostId) AS TotalPostsByThisUser,
    SUM(CASE WHEN updw.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsCount,
    SUM(CASE WHEN updw.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersCount,
    -- String aggregation and manipulation for user's question tags
    STRING_AGG(DISTINCT TRIM(REPLACE(REPLACE(sub.tag, '<', ''), '>', '')), ', ') FILTER (WHERE updw.PostTypeId = 1 AND updw.Tags IS NOT NULL) AS UserQuestionTags,
    SUM(CASE WHEN updw.Body LIKE '%performance%' OR updw.Body LIKE '%optimization%' THEN 1 ELSE 0 END) AS PerformanceRelatedPostsCount,
    MAX(CASE WHEN updw.ClosedDate IS NOT NULL THEN 'TRUE' ELSE 'FALSE' END) AS HasClosedPost,
    -- Ratio of closed posts using pre-calculated window function data
    CAST(SUM(CASE WHEN updw.CloseCount > 0 THEN 1 ELSE 0 END) AS DECIMAL) / NULLIF(COUNT(updw.PostId), 0) AS RatioOfClosedPosts,
    MAX(updw.ActualLastActivityDate) AS LastUserActivityOverall, -- Latest activity from either post or history
    MAX(COALESCE(cr.Name, 'N/A')) AS LastClosedReasonName,
    SUM(updw.UpVoteCount) AS TotalUpvotesReceivedOnPosts,
    SUM(updw.DownVoteCount) AS TotalDownvotesReceivedOnPosts,
    SUM(updw.FavoriteCountTotal) AS TotalFavoritesOnPosts,
    -- Fetch the latest running average and total views from window functions
    (SELECT RunningAvgPostScoreUser FROM UserPostDetailWithWindows WHERE UserId = u.Id ORDER BY PostCreationDate DESC LIMIT 1) AS LatestRunningAvgPostScore,
    (SELECT RunningTotalPostViewsUser FROM UserPostDetailWithWindows WHERE UserId = u.Id ORDER BY PostCreationDate DESC LIMIT 1) AS LatestRunningTotalPostViews,
    -- Join to PostLinks to see how many of a user's questions are linked by others and how many links they made
    COUNT(DISTINCT pl_target.RelatedPostId) AS TotalLinkedPostsByOthers, -- Posts where current user's post is a target of a link (LinkTypeId = 1)
    COUNT(DISTINCT pl_source.PostId) AS TotalLinksMadeToOtherPosts, -- Posts where current user's post links to others (LinkTypeId = 1)
    -- Set operator usage via subquery (combining highly upvoted posts with highly commented posts)
    (
        SELECT COUNT(DISTINCT post_impact.Id)
        FROM (
            -- Posts with significant score
            SELECT p_impact.Id
            FROM Posts AS p_impact
            WHERE p_impact.OwnerUserId = u.Id
              AND p_impact.Score > 50
            UNION ALL
            -- Posts with significant comment count
            SELECT p_impact.Id
            FROM Posts AS p_impact
            JOIN Comments AS c_impact ON p_impact.Id = c_impact.PostId
            WHERE p_impact.OwnerUserId = u.Id
            GROUP BY p_impact.Id
            HAVING COUNT(c_impact.Id) > 10
        ) AS post_impact
    ) AS HighImpactPostsCount
FROM Users AS u
LEFT JOIN UserEngagementRank AS eer ON u.Id = eer.UserId
LEFT JOIN UserBadgeSummary AS ubs ON u.Id = ubs.UserId -- Re-join for badge class breakdown in select
LEFT JOIN UserPostDetailWithWindows AS updw ON u.Id = updw.UserId
LEFT JOIN CloseReasonTypes AS cr ON CAST(updw.LastCloseReasonId AS SMALLINT) = cr.Id
LEFT JOIN PostLinks AS pl_target ON updw.PostId = pl_target.RelatedPostId AND pl_target.LinkTypeId = 1 -- Posts linked by others
LEFT JOIN PostLinks AS pl_source ON updw.PostId = pl_source.PostId AND pl_source.LinkTypeId = 1 -- Posts linking to others
LEFT JOIN LATERAL (SELECT UNNEST(string_to_array(SUBSTRING(updw.Tags, 2, LENGTH(updw.Tags) - 2), '><')) AS tag) AS sub ON updw.Tags IS NOT NULL -- Lateral join to unnest tags for string_agg
WHERE
    u.Reputation > 5000 -- Focus on more established users
    AND u.Views > 100 -- Users with at least some profile views
    AND (u.Location IS NOT NULL AND (u.Location LIKE '%USA%' OR u.Location LIKE '%Canada%' OR u.Location LIKE '%Germany%')) -- Users from specific regions, with NULL handling
    AND updw.PostId IS NOT NULL -- Ensure user has at least one post considered in updw
GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location, u.WebsiteUrl,
    eer.EngagementScore, eer.OverallEngagementRank, eer.TotalBadges,
    ubs.GoldBadges, ubs.SilverBadges, ubs.BronzeBadges
ORDER BY
    eer.EngagementScore DESC, u.Reputation DESC
LIMIT 1000;
