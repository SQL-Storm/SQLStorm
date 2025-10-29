-- {"query": "1709.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 4599} 

WITH UserBaseMetrics AS (
    -- CTE 1: Calculates fundamental user statistics based on their posts and profile
    SELECT
        u.Id AS UserId,
        u.DisplayName AS UserName,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate AS UserLastAccessDate,
        u.Reputation,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        -- Calculate user age in days
        EXTRACT(EPOCH FROM (u.LastAccessDate - u.CreationDate)) / (60 * 60 * 24) AS UserAgeDays,
        -- Aggregate post scores and counts, defaulting to 0 for users with no posts
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COALESCE(COUNT(DISTINCT p.Id), 0) AS TotalPosts,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS TotalQuestions,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalAnswers,
        COALESCE(AVG(p.Score) FILTER (WHERE p.PostTypeId = 1), 0.0) AS AvgQuestionScore,
        COALESCE(AVG(p.Score) FILTER (WHERE p.PostTypeId = 2), 0.0) AS AvgAnswerScore
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    GROUP BY
        u.Id, u.DisplayName, u.CreationDate, u.LastAccessDate, u.Reputation, u.UpVotes, u.DownVotes
),
PostEngagementMetrics AS (
    -- CTE 2: Gathers detailed engagement metrics for each post, including comments and related posts
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.LastActivityDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.AcceptedAnswerId IS NOT NULL AS HasAcceptedAnswer,
        -- Calculate days since last activity
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - p.LastActivityDate)) / (60 * 60 * 24) AS DaysSinceLastActivity,
        LENGTH(p.Body) AS BodyLength,
        COALESCE(SUM(c.Score), 0) AS TotalCommentScore,
        COALESCE(COUNT(DISTINCT c.Id), 0) AS UniqueCommenters,
        -- Correlated subquery to find the most recent edit date for the post
        (SELECT MAX(ph_edit.CreationDate) FROM PostHistory ph_edit WHERE ph_edit.PostId = p.Id AND ph_edit.PostHistoryTypeId IN (4,5,6)) AS LastEditDate,
        COALESCE(COUNT(DISTINCT pl_linked.RelatedPostId) FILTER (WHERE pl_linked.LinkTypeId = 1), 0) AS LinkedPostCount,
        COALESCE(COUNT(DISTINCT pl_duplicate.RelatedPostId) FILTER (WHERE pl_duplicate.LinkTypeId = 3), 0) AS DuplicateOfCount
    FROM
        Posts p
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    LEFT JOIN
        PostLinks pl_linked ON p.Id = pl_linked.PostId AND pl_linked.LinkTypeId = 1
    LEFT JOIN
        PostLinks pl_duplicate ON p.Id = pl_duplicate.PostId AND pl_duplicate.LinkTypeId = 3
    GROUP BY
        p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.LastActivityDate, p.Score, p.ViewCount,
        p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ClosedDate, p.AcceptedAnswerId
),
TagEngagementStats AS (
    -- CTE 3: Analyzes performance and popularity of tags based on associated questions
    SELECT
        unnest_tags.tag_name AS TagName,
        COUNT(DISTINCT p.Id) AS TaggedQuestionCount,
        COALESCE(AVG(p.Score), 0.0) AS AvgScoreForTaggedQuestions,
        COALESCE(SUM(p.ViewCount), 0) AS TotalTagViews,
        -- Rank tags by their popularity (question count and average score)
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC, COALESCE(AVG(p.Score), 0.0) DESC) AS TagPopularityRank
    FROM
        Posts p
    CROSS JOIN LATERAL
        -- Use string_to_array and UNNEST for robust tag parsing
        (SELECT TRIM(UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><'))) AS tag_name) AS unnest_tags
    WHERE
        p.PostTypeId = 1 AND p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2 AND unnest_tags.tag_name IS NOT NULL
    GROUP BY
        unnest_tags.tag_name
),
AdvancedPostHistoryAnalysis AS (
    -- CTE 4: Delves into post history events, calculating time differences and first close dates
    SELECT
        ph.PostId,
        ph.PostHistoryTypeId,
        pht.Name AS HistoryTypeName,
        ph.CreationDate AS HistoryEventDate,
        ph.UserId AS HistoryTriggerUserId,
        -- Use LAG to find the time difference between consecutive history events for a post
        LAG(ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PreviousEventDate,
        EXTRACT(EPOCH FROM (ph.CreationDate - LAG(ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate))) / (60 * 60) AS HoursSincePreviousEvent,
        -- NTILE to categorize history events into time quartiles
        NTILE(4) OVER (ORDER BY ph.CreationDate) AS TimeQuartileOverall,
        -- Correlated subquery to find the absolute initial creation date from PostHistory
        (SELECT MIN(ph_init.CreationDate) FROM PostHistory ph_init WHERE ph_init.PostId = ph.PostId AND ph_init.PostHistoryTypeId IN (1,2,3)) AS InitialPostCreationDate,
        -- Correlated subquery to find the first recorded close date for the post
        (SELECT MIN(ph_close.CreationDate) FROM PostHistory ph_close WHERE ph_close.PostId = ph.PostId AND ph_close.PostHistoryTypeId = 10) AS FirstClosedDate
    FROM
        PostHistory ph
    JOIN
        PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE
        ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 10, 11, 12, 13) -- Focus on key initial, edit, close/reopen, delete/undelete events
),
UserBadgeContributions AS (
    -- CTE 5: Examines user badge acquisition and related metrics
    SELECT
        b.UserId,
        b.Id AS BadgeId,
        b.Name AS BadgeName,
        b.Class AS BadgeClass,
        b.Date AS BadgeAwardDate,
        -- Total badges a user has received
        COUNT(b.Id) OVER (PARTITION BY b.UserId) AS TotalBadgesForUser,
        -- Sequence number for badge acquisition
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date) AS BadgeAcquisitionSequence,
        -- Last date a user received a Gold badge (Class = 1)
        MAX(CASE WHEN b.Class = 1 THEN b.Date ELSE NULL END) OVER (PARTITION BY b.UserId) AS LastGoldBadgeDate,
        -- Count of Gold badges, using NULLIF to avoid counting 0 as an actual badge count
        COALESCE(NULLIF(SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) OVER (PARTITION BY b.UserId), 0), 0) AS GoldBadgeCount
    FROM
        Badges b
    WHERE
        b.TagBased = FALSE -- Focus on named badges, not tag-based ones
),
PostVoteAggregates AS (
    -- CTE 6: Aggregates various vote types for each post
    SELECT
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS TotalFavorites,
        SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) AS TotalBountyStarted,
        SUM(CASE WHEN v.VoteTypeId = 9 THEN v.BountyAmount ELSE 0 END) AS TotalBountyClosed
    FROM
        Votes v
    GROUP BY
        v.PostId
),
CombinedPostAnalysis AS (
    -- CTE 7: Consolidates metrics from PostEngagementMetrics, AdvancedPostHistoryAnalysis, and PostVoteAggregates
    SELECT
        p.PostId,
        p.PostTypeId,
        p.PostCreationDate,
        p.OwnerUserId,
        p.PostScore,
        p.ViewCount,
        p.CommentCount,
        p.AnswerCount,
        p.BodyLength,
        p.LastEditDate,
        p.DaysSinceLastActivity,
        p.HasAcceptedAnswer,
        p.TotalCommentScore,
        p.UniqueCommenters,
        p.LinkedPostCount,
        p.DuplicateOfCount,
        pha.InitialPostCreationDate,
        pha.FirstClosedDate,
        EXTRACT(EPOCH FROM (pha.FirstClosedDate - p.PostCreationDate)) / (60 * 60 * 24) AS DaysToFirstClose,
        -- Another correlated subquery to find the latest overall history event date for a post
        (SELECT ph_latest.HistoryEventDate FROM AdvancedPostHistoryAnalysis ph_latest WHERE ph_latest.PostId = p.PostId ORDER BY ph_latest.HistoryEventDate DESC LIMIT 1) AS LatestHistoryEventDate,
        pv.TotalUpVotes,
        pv.TotalDownVotes,
        pv.TotalFavorites,
        pv.TotalBountyStarted,
        pv.TotalBountyClosed
    FROM
        PostEngagementMetrics p
    LEFT JOIN
        AdvancedPostHistoryAnalysis pha ON p.PostId = pha.PostId AND pha.PostHistoryTypeId IN (10, 11) -- Only join for close/reopen events once
    LEFT JOIN
        PostVoteAggregates pv ON p.Id = pv.PostId
    WHERE
        p.PostTypeId IN (1, 2) -- Focus on Questions and Answers
    GROUP BY
        p.PostId, p.PostTypeId, p.PostCreationDate, p.OwnerUserId, p.PostScore, p.ViewCount, p.CommentCount,
        p.AnswerCount, p.BodyLength, p.LastEditDate, p.DaysSinceLastActivity, p.HasAcceptedAnswer,
        p.TotalCommentScore, p.UniqueCommenters, p.LinkedPostCount, p.DuplicateOfCount,
        pha.InitialPostCreationDate, pha.FirstClosedDate,
        pv.TotalUpVotes, pv.TotalDownVotes, pv.TotalFavorites, pv.TotalBountyStarted, pv.TotalBountyClosed
),
FinalResult AS (
    -- CTE 8: Joins all previous CTEs and applies complex calculations and window functions
    SELECT
        ubm.UserId,
        ubm.UserName,
        ubm.Reputation,
        ubm.UserAgeDays,
        ubm.TotalPosts,
        ubm.TotalQuestions,
        ubm.TotalAnswers,
        ubm.AvgQuestionScore,
        ubm.AvgAnswerScore,
        cpa.PostId,
        pt.Name AS PostTypeName,
        cpa.PostScore,
        cpa.ViewCount,
        cpa.CommentCount,
        cpa.AnswerCount,
        cpa.BodyLength,
        cpa.DaysSinceLastActivity,
        cpa.HasAcceptedAnswer,
        cpa.TotalCommentScore,
        cpa.UniqueCommenters,
        cpa.LinkedPostCount,
        cpa.DuplicateOfCount,
        cpa.DaysToFirstClose,
        cpa.LatestHistoryEventDate,
        cpa.TotalUpVotes,
        cpa.TotalDownVotes,
        cpa.TotalFavorites,
        cpa.TotalBountyStarted,
        cpa.TotalBountyClosed,
        ubc.BadgeName AS FirstBadgeName,
        ubc.BadgeClass AS FirstBadgeClass,
        ubc.BadgeAwardDate AS FirstBadgeAwardDate,
        ubc.TotalBadgesForUser,
        ubc.GoldBadgeCount,
        tes.TagName AS TopContributingTag,
        tes.TaggedQuestionCount AS TopTagQuestionCount,
        tes.AvgScoreForTaggedQuestions AS TopTagAvgScore,
        tes.TagPopularityRank AS TopTagRank,
        COALESCE(NULLIF(cpa.ViewCount, 0), 0) AS ViewCountNonNull, -- Demonstrates NULLIF for division by zero and COALESCE
        COALESCE(cpa.TotalCommentScore, 0) / NULLIF(cpa.CommentCount, 0) AS AvgCommentScorePerPost, -- Division by zero handling
        LOWER(SUBSTRING(ubm.UserName, 1, 3) || '_' || REPLACE(TRIM(ubm.UserName), ' ', '-')) AS UserIdentifierHash, -- Complex string manipulation
        ROW_NUMBER() OVER (PARTITION BY ubm.Reputation / 1000 ORDER BY cpa.PostScore DESC, cpa.ViewCount DESC) AS RankWithinReputationTier,
        AVG(cpa.PostScore) OVER (PARTITION BY pt.Name ORDER BY cpa.PostCreationDate ROWS BETWEEN 30 PRECEDING AND CURRENT ROW) AS RollingAvgPostScoreByPostType,
        CASE -- Complex conditional logic for post lifecycle status
            WHEN cpa.DaysToFirstClose IS NOT NULL AND cpa.DaysToFirstClose <= 7 THEN 'QuicklyClosed'
            WHEN cpa.DaysToFirstClose IS NOT NULL AND cpa.DaysToFirstClose > 7 THEN 'LaterClosed'
            WHEN cpa.HasAcceptedAnswer THEN 'AcceptedAnswer'
            ELSE 'OpenOrNoAnswer'
        END AS PostLifecycleStatus,
        COUNT(cpa.PostId) OVER (PARTITION BY ubm.UserId) AS UserPostCountInResult,
        -- Non-correlated subquery to calculate a dynamic performance threshold for comparison
        (SELECT AVG(p_avg.ViewCount * p_avg.Score) * 1.5 FROM Posts p_avg WHERE p_avg.PostTypeId = cpa.PostTypeId) AS HighPerformanceThreshold
    FROM
        UserBaseMetrics ubm
    LEFT JOIN
        CombinedPostAnalysis cpa ON ubm.UserId = cpa.OwnerUserId
    LEFT JOIN
        PostTypes pt ON cpa.PostTypeId = pt.Id
    LEFT JOIN
        (SELECT UserId, BadgeName, BadgeClass, BadgeAwardDate, TotalBadgesForUser, GoldBadgeCount FROM UserBadgeContributions WHERE BadgeAcquisitionSequence = 1) ubc ON ubm.UserId = ubc.UserId
    LEFT JOIN LATERAL ( -- Lateral join to find the user's top contributing tag (correlated subquery behavior)
        SELECT tes.TagName, tes.TaggedQuestionCount, tes.AvgScoreForTaggedQuestions, tes.TagPopularityRank
        FROM TagEngagementStats tes
        WHERE tes.TagName IN (
            SELECT TRIM(UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><')))
            FROM Posts p
            WHERE p.OwnerUserId = ubm.UserId AND p.PostTypeId = 1 AND p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2
            ORDER BY p.Score DESC
            LIMIT 1
        )
        ORDER BY tes.TaggedQuestionCount DESC, tes.AvgScoreForTaggedQuestions DESC
        LIMIT 1
    ) tes ON true
    WHERE
        ubm.Reputation > 1000 AND cpa.PostScore > 5 -- Base filters
        AND ubm.UserCreationDate >= '2015-01-01'
        AND cpa.PostCreationDate <= CURRENT_DATE - INTERVAL '30 day' -- Exclude very recent data
        AND (cpa.BodyLength > 500 OR cpa.TotalCommentScore > 10) -- Complex predicate
        AND NOT EXISTS ( -- Anti-join using NOT EXISTS to filter out posts that were deleted and never undeleted
            SELECT 1
            FROM PostHistory ph_del
            WHERE ph_del.PostId = cpa.PostId AND ph_del.PostHistoryTypeId = 12
            GROUP BY ph_del.PostId
            HAVING COUNT(CASE WHEN ph_del.PostHistoryTypeId = 13 THEN 1 ELSE NULL END) = 0
        )
),
HighPerformingPosts AS (
    -- Selects posts that exceed the dynamic performance threshold
    SELECT *
    FROM FinalResult
    WHERE (PostScore * ViewCount) >= HighPerformanceThreshold
),
AveragePerformingPosts AS (
    -- Selects posts that fall below the dynamic performance threshold
    SELECT *
    FROM FinalResult
    WHERE (PostScore * ViewCount) < HighPerformanceThreshold
)
-- Main query: Combines results from high-performing questions with bounties,
-- and average-performing answers that were accepted, using UNION ALL.
SELECT
    UserId, UserName, Reputation, UserAgeDays, TotalPosts, TotalQuestions, TotalAnswers, AvgQuestionScore, AvgAnswerScore,
    PostId, PostTypeName, PostScore, ViewCount, CommentCount, AnswerCount, BodyLength, DaysSinceLastActivity,
    HasAcceptedAnswer, TotalCommentScore, UniqueCommenters, LinkedPostCount, DuplicateOfCount, DaysToFirstClose,
    LatestHistoryEventDate, TotalUpVotes, TotalDownVotes, TotalFavorites, TotalBountyStarted, TotalBountyClosed,
    FirstBadgeName, FirstBadgeClass, FirstBadgeAwardDate, TotalBadgesForUser, GoldBadgeCount, TopContributingTag,
    TopTagQuestionCount, TopTagAvgScore, TopTagRank, ViewCountNonNull, AvgCommentScorePerPost, UserIdentifierHash,
    RankWithinReputationTier, RollingAvgPostScoreByPostType, PostLifecycleStatus, UserPostCountInResult
FROM HighPerformingPosts
WHERE PostTypeName = 'Question' AND TotalBountyStarted > 0

UNION ALL

SELECT
    UserId, UserName, Reputation, UserAgeDays, TotalPosts, TotalQuestions, TotalAnswers, AvgQuestionScore, AvgAnswerScore,
    PostId, PostTypeName, PostScore, ViewCount, CommentCount, AnswerCount, BodyLength, DaysSinceLastActivity,
    HasAcceptedAnswer, TotalCommentScore, UniqueCommenters, LinkedPostCount, DuplicateOfCount, DaysToFirstClose,
    LatestHistoryEventDate, TotalUpVotes, TotalDownVotes, TotalFavorites, TotalBountyStarted, TotalBountyClosed,
    FirstBadgeName, FirstBadgeClass, FirstBadgeAwardDate, TotalBadgesForUser, GoldBadgeCount, TopContributingTag,
    TopTagQuestionCount, TopTagAvgScore, TopTagRank, ViewCountNonNull, AvgCommentScorePerPost, UserIdentifierHash,
    RankWithinReputationTier, RollingAvgPostScoreByPostType, PostLifecycleStatus, UserPostCountInResult
FROM AveragePerformingPosts
WHERE PostTypeName = 'Answer' AND HasAcceptedAnswer = TRUE

ORDER BY
    Reputation DESC, PostScore DESC, ViewCount DESC
LIMIT 10000;
