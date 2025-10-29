-- {"query": "1330.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 4127} 

WITH UserEngagementSummary AS (
    -- CTE 1: Aggregates core user activity, reputation, and basic post metrics.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.UpVotes,
        u.DownVotes,
        u.Views AS UserProfileViews,
        COUNT(DISTINCT p_owned.Id) AS TotalPostsOwned,
        SUM(CASE WHEN p_owned.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsOwned,
        SUM(CASE WHEN p_owned.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersOwned,
        SUM(COALESCE(p_owned.Score, 0)) AS TotalPostsScore,
        AVG(COALESCE(p_owned.ViewCount, 0)) AS AvgPostViewCount,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        MAX(p_owned.LastActivityDate) AS LastPostActivityDate,
        MAX(c.CreationDate) AS LastCommentActivityDate,
        CAST(SUM(COALESCE(p_owned.Score, 0)) AS DECIMAL(10,2)) / NULLIF(COUNT(DISTINCT p_owned.Id), 0) AS AvgScorePerOwnedPost
    FROM Users AS u
    LEFT JOIN Posts AS p_owned ON u.Id = p_owned.OwnerUserId
    LEFT JOIN Comments AS c ON u.Id = c.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
        u.UpVotes, u.DownVotes, u.Views
),
PostVoteDetails AS (
    -- CTE 2: Captures vote and closure status for posts, along with basic metadata.
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score AS CurrentPostScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.Title,
        p.Tags,
        p.ClosedDate,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        MAX(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS IsClosedFlag,
        MAX(CASE WHEN p.AcceptedAnswerId IS NOT NULL AND p.PostTypeId = 1 THEN 1 ELSE 0 END) AS HasAcceptedAnswer
    FROM Posts AS p
    LEFT JOIN Votes AS v ON p.Id = v.PostId
    GROUP BY
        p.Id, p.OwnerUserId, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount,
        p.AnswerCount, p.CommentCount, p.FavoriteCount, p.Title, p.Tags, p.ClosedDate
),
UserTagContributionMetrics AS (
    -- CTE 3: Analyzes user's contribution to specific tags, including performance.
    -- Assumes PostgreSQL-like `string_to_array` and `unnest`.
    SELECT
        pvd.OwnerUserId AS UserId,
        LOWER(TRIM(unnested_tag)) AS TagName,
        COUNT(DISTINCT pvd.PostId) AS TagPostsCount,
        SUM(pvd.CurrentPostScore) AS TagTotalScore,
        AVG(pvd.CurrentPostScore) AS TagAvgScore,
        MIN(pvd.PostCreationDate) AS FirstTagPostDate,
        MAX(pvd.PostCreationDate) AS LastTagPostDate,
        SUM(pvd.UpVoteCount) AS TagUpvotes,
        SUM(pvd.DownVoteCount) AS TagDownvotes
    FROM PostVoteDetails AS pvd
    WHERE pvd.OwnerUserId IS NOT NULL AND pvd.Tags IS NOT NULL AND LENGTH(pvd.Tags) > 2
    CROSS JOIN LATERAL UNNEST(string_to_array(SUBSTRING(pvd.Tags FROM 2 FOR LENGTH(pvd.Tags) - 2), '><')) AS unnested_tag
    GROUP BY pvd.OwnerUserId, LOWER(TRIM(unnested_tag))
    HAVING COUNT(DISTINCT pvd.PostId) >= 3 -- Focus on users with significant activity in a tag
),
RecentPostPerformance AS (
    -- CTE 4: Ranks user's recent posts by score and identifies trends.
    SELECT
        pvd.OwnerUserId AS UserId,
        pvd.PostId,
        pvd.Title,
        pvd.CurrentPostScore,
        pvd.PostCreationDate,
        ROW_NUMBER() OVER(PARTITION BY pvd.OwnerUserId ORDER BY pvd.CurrentPostScore DESC, pvd.PostCreationDate DESC) AS ScoreRankDesc,
        DENSE_RANK() OVER(PARTITION BY pvd.OwnerUserId ORDER BY pvd.PostCreationDate DESC) AS RecentDateRank,
        LAG(pvd.CurrentPostScore, 1, 0) OVER(PARTITION BY pvd.OwnerUserId ORDER BY pvd.PostCreationDate) AS PrevPostScore,
        LEAD(pvd.CurrentPostScore, 1, 0) OVER(PARTITION BY pvd.OwnerUserId ORDER BY pvd.PostCreationDate) AS NextPostScore
    FROM PostVoteDetails AS pvd
    WHERE
        pvd.OwnerUserId IS NOT NULL
        AND pvd.PostCreationDate >= (NOW() - INTERVAL '1 year')
        AND pvd.PostTypeId IN (1, 2) -- Questions and Answers
),
UserEditAndClosureActivity AS (
    -- CTE 5: Details user's post editing and involvement in closure/reopen processes.
    SELECT
        ph.UserId,
        COUNT(ph.Id) AS TotalHistoryEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS ContentEditCount,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (10, 11) THEN 1 ELSE 0 END) AS CloseReopenVoteCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 AND ph.Comment IS NOT NULL AND LENGTH(ph.Comment) > 0 THEN 1 ELSE 0 END) AS ClosedByReasonCount,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.PostId END) AS UniquePostsClosedByMe,
        MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory AS ph
    WHERE ph.UserId IS NOT NULL
    GROUP BY ph.UserId
),
UserOverallMetrics AS (
    -- CTE 6: Consolidates all user-specific metrics from previous CTEs.
    SELECT
        ues.UserId,
        ues.DisplayName,
        ues.Reputation,
        ues.UserCreationDate,
        ues.LastAccessDate,
        ues.TotalPostsOwned,
        ues.TotalQuestionsOwned,
        ues.TotalAnswersOwned,
        ues.TotalPostsScore,
        ues.AvgScorePerOwnedPost,
        ues.TotalCommentsMade,
        COALESCE(ueca.ContentEditCount, 0) AS TotalContentEdits,
        COALESCE(ueca.CloseReopenVoteCount, 0) AS TotalCloseReopenVotes,
        COALESCE(ueca.UniquePostsClosedByMe, 0) AS UniqueClosedPostsInvolved,
        -- Correlated subquery: Count posts owned by this user that are currently closed
        (SELECT COUNT(DISTINCT pvd_sub.PostId)
         FROM PostVoteDetails AS pvd_sub
         WHERE pvd_sub.OwnerUserId = ues.UserId
           AND pvd_sub.IsClosedFlag = 1
           AND pvd_sub.OwnerUserId IS NOT NULL
        ) AS OwnActiveClosedPosts,
        -- Calculate the reputation density: Reputation / (Age in days + 1)
        CAST(ues.Reputation AS DECIMAL(15,2)) / NULLIF(EXTRACT(EPOCH FROM (NOW() - ues.UserCreationDate)) / (24*60*60) + 1, 0) AS ReputationDensity
    FROM UserEngagementSummary AS ues
    LEFT JOIN UserEditAndClosureActivity AS ueca ON ues.UserId = ueca.UserId
),
TopTierContributors AS (
    -- Segment A: Users excelling in multiple areas with high engagement and impact.
    SELECT
        uom.UserId,
        uom.DisplayName,
        'TopTierContributor' AS UserSegment,
        uom.Reputation,
        uom.TotalPostsOwned,
        uom.TotalAnswersOwned,
        uom.TotalContentEdits,
        uom.AvgScorePerOwnedPost,
        STRING_AGG(DISTINCT utcm.TagName, ' | ') FILTER (WHERE utcm.TagPostsCount >= 10 AND utcm.TagTotalScore >= 100) AS KeyInfluentialTags,
        COUNT(DISTINCT utcm.TagName) FILTER (WHERE utcm.TagPostsCount >= 10 AND utcm.TagTotalScore >= 100) AS NumKeyInfluentialTags,
        MAX(rpc.CurrentPostScore) FILTER (WHERE rpc.ScoreRankDesc = 1) AS HighestScoringRecentPostScore,
        MAX(rpc.Title) FILTER (WHERE rpc.ScoreRankDesc = 1) AS HighestScoringRecentPostTitle,
        uom.ReputationDensity,
        (SELECT AVG(Reputation) FROM Users WHERE LastAccessDate >= (NOW() - INTERVAL '1 year')) AS GlobalActiveUserAvgReputation -- Non-correlated subquery
    FROM UserOverallMetrics AS uom
    LEFT JOIN UserTagContributionMetrics AS utcm ON uom.UserId = utcm.UserId
    LEFT JOIN RecentPostPerformance AS rpc ON uom.UserId = rpc.UserId
    WHERE
        uom.Reputation >= 15000
        AND uom.TotalAnswersOwned >= 100
        AND uom.TotalContentEdits >= 50
        AND uom.LastAccessDate >= (NOW() - INTERVAL '6 months')
    GROUP BY
        uom.UserId, uom.DisplayName, uom.Reputation, uom.TotalPostsOwned,
        uom.TotalAnswersOwned, uom.TotalContentEdits, uom.AvgScorePerOwnedPost,
        uom.ReputationDensity
),
ControversialYetActiveUsers AS (
    -- Segment B: Active users who have posts with significant downvotes or have been involved in closures.
    SELECT
        uom.UserId,
        uom.DisplayName,
        'ControversialYetActive' AS UserSegment,
        uom.Reputation,
        uom.TotalPostsOwned,
        uom.TotalQuestionsOwned,
        uom.TotalCloseReopenVotes,
        uom.OwnActiveClosedPosts,
        SUM(pvd.DownVoteCount) AS TotalDownvotesReceivedOnPosts,
        AVG(CASE WHEN pvd.PostTypeId = 1 THEN pvd.CurrentPostScore ELSE NULL END) AS AvgQuestionScore,
        AVG(rpc.PrevPostScore - rpc.CurrentPostScore) AS AvgScoreDropFromPreviousPost,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY pvd.CurrentPostScore) OVER (PARTITION BY uom.UserId) AS MedianPostScore
    FROM UserOverallMetrics AS uom
    LEFT JOIN PostVoteDetails AS pvd ON uom.UserId = pvd.OwnerUserId
    LEFT JOIN RecentPostPerformance AS rpc ON uom.UserId = rpc.UserId
    WHERE
        uom.Reputation >= 1000
        AND uom.LastAccessDate >= (NOW() - INTERVAL '1 year')
        AND (uom.OwnActiveClosedPosts > 0 OR uom.TotalCloseReopenVotes > 5)
    GROUP BY
        uom.UserId, uom.DisplayName, uom.Reputation, uom.TotalPostsOwned,
        uom.TotalQuestionsOwned, uom.TotalCloseReopenVotes, uom.OwnActiveClosedPosts
    HAVING SUM(pvd.DownVoteCount) > 20 -- Ensure some downvote activity
)
-- Final Query: Combines the two segments, adding more complex calculations and conditional logic.
SELECT
    f.UserId,
    f.DisplayName,
    f.UserSegment,
    f.Reputation,
    f.TotalPostsOwned,
    COALESCE(f.TotalQuestionsOwned, 0) AS TotalQuestionsOwned,
    COALESCE(f.TotalAnswersOwned, 0) AS TotalAnswersOwned,
    f.TotalContentEdits,
    f.AvgScorePerOwnedPost,
    f.KeyInfluentialTags,
    f.NumKeyInfluentialTags,
    f.HighestScoringRecentPostScore,
    f.HighestScoringRecentPostTitle,
    COALESCE(f.TotalDownvotesReceivedOnPosts, 0) AS TotalDownvotesReceivedOnPosts,
    COALESCE(f.OwnActiveClosedPosts, 0) AS OwnActiveClosedPosts,
    COALESCE(f.ReputationDensity, 0.0) AS ReputationDensity,
    COALESCE(f.GlobalActiveUserAvgReputation, 0.0) AS GlobalActiveUserAvgReputation,
    COALESCE(f.AvgQuestionScore, 0.0) AS AvgQuestionScore,
    COALESCE(f.AvgScoreDropFromPreviousPost, 0.0) AS AvgScoreDropFromPreviousPost,
    COALESCE(f.MedianPostScore, 0.0) AS MedianPostScore,
    -- Complex calculation: "Impact Score" considering reputation, post score, and edits, with a penalty for closed posts.
    (f.Reputation * 0.5 + COALESCE(f.AvgScorePerOwnedPost, 0) * 2 + COALESCE(f.TotalContentEdits, 0) * 0.1)
    - (COALESCE(f.OwnActiveClosedPosts, 0) * 100 + COALESCE(f.TotalDownvotesReceivedOnPosts, 0) * 0.5) AS UserImpactScore,
    -- NULL logic and complicated string expression
    COALESCE(
        CASE
            WHEN f.NumKeyInfluentialTags IS NOT NULL AND f.NumKeyInfluentialTags > 0
            THEN 'Influencer (' || CAST(f.NumKeyInfluentialTags AS VARCHAR) || ' Tags)'
            ELSE NULL
        END,
        CASE
            WHEN f.TotalAnswersOwned > f.TotalQuestionsOwned * 2 THEN 'Answerer Focus'
            WHEN f.TotalQuestionsOwned > f.TotalAnswersOwned * 2 THEN 'Questioner Focus'
            ELSE 'Balanced Contributor'
        END
    ) AS ContributionTypeClassification,
    CASE
        WHEN f.UserSegment = 'TopTierContributor' AND f.UserId IN (SELECT UserId FROM ControversialYetActiveUsers) THEN 'Overlap: TopTier & Controversial'
        WHEN f.UserSegment = 'TopTierContributor' THEN 'Pure TopTier'
        WHEN f.UserSegment = 'ControversialYetActive' THEN 'Pure Controversial'
        ELSE 'Unknown Segment'
    END AS SegmentOverlapStatus
FROM (
    SELECT
        ttc.UserId,
        ttc.DisplayName,
        ttc.UserSegment,
        ttc.Reputation,
        ttc.TotalPostsOwned,
        ttc.TotalQuestionsOwned,
        ttc.TotalAnswersOwned,
        ttc.TotalContentEdits,
        ttc.AvgScorePerOwnedPost,
        ttc.KeyInfluentialTags,
        ttc.NumKeyInfluentialTags,
        ttc.HighestScoringRecentPostScore,
        ttc.HighestScoringRecentPostTitle,
        NULL::BIGINT AS TotalDownvotesReceivedOnPosts, -- Cast to match type for UNION ALL
        NULL::INT AS OwnActiveClosedPosts,
        ttc.ReputationDensity,
        ttc.GlobalActiveUserAvgReputation,
        NULL::DECIMAL(10,2) AS AvgQuestionScore,
        NULL::DECIMAL(10,2) AS AvgScoreDropFromPreviousPost,
        NULL::DECIMAL(10,2) AS MedianPostScore
    FROM TopTierContributors AS ttc

    UNION ALL

    SELECT
        cau.UserId,
        cau.DisplayName,
        cau.UserSegment,
        cau.Reputation,
        cau.TotalPostsOwned,
        cau.TotalQuestionsOwned,
        NULL AS TotalAnswersOwned,
        cau.TotalContentEdits,
        cau.AvgScorePerOwnedPost,
        NULL AS KeyInfluentialTags,
        NULL::BIGINT AS NumKeyInfluentialTags, -- Cast to match type for UNION ALL
        NULL::INT AS HighestScoringRecentPostScore,
        NULL AS HighestScoringRecentPostTitle,
        cau.TotalDownvotesReceivedOnPosts,
        cau.OwnActiveClosedPosts,
        uom_ref.ReputationDensity, -- Re-fetch from UOM for consistency, or pass through
        (SELECT AVG(Reputation) FROM Users WHERE LastAccessDate >= (NOW() - INTERVAL '1 year')) AS GlobalActiveUserAvgReputation,
        cau.AvgQuestionScore,
        cau.AvgScoreDropFromPreviousPost,
        cau.MedianPostScore
    FROM ControversialYetActiveUsers AS cau
    INNER JOIN UserOverallMetrics AS uom_ref ON cau.UserId = uom_ref.UserId -- Join to get ReputationDensity
) AS f
WHERE
    f.Reputation > 500 -- Minimum threshold for relevance
    AND (f.TotalPostsOwned > 5 OR f.TotalContentEdits > 5) -- Ensure some activity
ORDER BY
    f.UserImpactScore DESC, f.Reputation DESC
LIMIT 200;
