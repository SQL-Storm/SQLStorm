-- {"query": "1133.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3793} 

WITH UserEngagementMetrics AS (
    -- CTE 1: Aggregates core engagement metrics for users within a specific activity window.
    -- Focuses on reputation, posts, answers, comments, and recent activity.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views AS UserProfileViews,
        u.UpVotes AS UserTotalUpVotes,
        u.DownVotes AS UserTotalDownVotes,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersProvided,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT b.Id) AS TotalBadgesEarned,
        SUM(COALESCE(p.Score, 0)) AS SumPostScores,
        SUM(COALESCE(p.ViewCount, 0)) AS SumPostViews,
        MAX(p.LastActivityDate) AS LastPostActivityDate,
        MIN(p.CreationDate) AS FirstPostCreationDate,
        (SELECT COUNT(DISTINCT ph.PostId) FROM PostHistory ph WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId IN (4, 5, 6)) AS SelfEditedPostsCount,
        (SELECT COUNT(DISTINCT v.Id) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 8) AS BountiesStartedCount -- VoteType 8 = BountyStart
    FROM
        Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE
        u.CreationDate >= '2020-01-01'
        AND u.Reputation > 500
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
PostQualityIndicators AS (
    -- CTE 2: Evaluates post quality, focusing on questions and their interaction metrics,
    -- including analysis of accepted answers and tags.
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.CreationDate AS PostCreationDate,
        p.AcceptedAnswerId,
        STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><') AS PostTags,
        (SELECT COUNT(v.Id) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpvotesReceived, -- VoteType 2 = UpMod
        (SELECT COUNT(v.Id) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownvotesReceived, -- VoteType 3 = DownMod
        CASE
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Accepted'
            WHEN p.AnswerCount > 0 AND p.Score > 10 THEN 'Highly Answered'
            WHEN p.ViewCount > 5000 AND p.FavoriteCount > 50 THEN 'Popular'
            ELSE 'Standard'
        END AS PostStatusCategory,
        (EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate)) / 3600.0) AS HoursSinceCreationToLastActivity -- Time in hours
    FROM
        Posts p
    WHERE
        p.PostTypeId = 1 -- Only questions
        AND p.CreationDate >= '2020-01-01'
        AND p.Tags IS NOT NULL
        AND p.ViewCount > 500
),
UserActivityTimeline AS (
    -- CTE 3: Analyzes a user's chronological activity, specifically for posts,
    -- using window functions to identify posting frequency and score trends.
    SELECT
        pq.OwnerUserId AS UserId,
        pq.PostId,
        pq.PostCreationDate,
        pq.Score AS PostScore,
        pq.UpvotesReceived,
        pq.DownvotesReceived,
        pq.PostStatusCategory,
        LAG(pq.PostCreationDate, 1, pq.PostCreationDate) OVER (PARTITION BY pq.OwnerUserId ORDER BY pq.PostCreationDate) AS PreviousPostDate,
        (pq.PostCreationDate - LAG(pq.PostCreationDate, 1, pq.PostCreationDate) OVER (PARTITION BY pq.OwnerUserId ORDER BY pq.PostCreationDate)) AS TimeSincePreviousPost,
        ROW_NUMBER() OVER (PARTITION BY pq.OwnerUserId ORDER BY pq.PostCreationDate) AS PostSequenceNum,
        RANK() OVER (PARTITION BY pq.OwnerUserId ORDER BY pq.Score DESC) AS RankByScoreForUser,
        NTILE(5) OVER (PARTITION BY pq.OwnerUserId ORDER BY pq.Score DESC) AS ScoreNtileForUser
    FROM
        PostQualityIndicators pq
    WHERE
        pq.OwnerUserId IS NOT NULL
),
UserContributionSummary AS (
    -- CTE 4: Consolidates user-level metrics from engagement and post quality,
    -- adding complex calculations and correlated subqueries.
    SELECT
        uem.UserId,
        uem.DisplayName,
        uem.Reputation,
        uem.UserProfileViews,
        uem.UserTotalUpVotes,
        uem.UserTotalDownVotes,
        uem.TotalPosts,
        uem.QuestionsAsked,
        uem.AnswersProvided,
        uem.TotalComments,
        uem.TotalBadgesEarned,
        uem.SumPostScores,
        uem.SumPostViews,
        uem.SelfEditedPostsCount,
        uem.BountiesStartedCount,
        AVG(EXTRACT(EPOCH FROM uat.TimeSincePreviousPost)) FILTER (WHERE uat.TimeSincePreviousPost IS NOT NULL) AS AvgSecondsBetweenPosts,
        MAX(uat.PostScore) AS HighestPostScore,
        SUM(CASE WHEN uat.PostStatusCategory = 'Accepted' THEN 1 ELSE 0 END) AS AcceptedAnswersForTheirQuestions,
        COUNT(DISTINCT pl.RelatedPostId) FILTER (WHERE pl.LinkTypeId = 3) AS LinkedDuplicateQuestions, -- LinkType 3 = Duplicate
        (
            SELECT SUM(p.Score)
            FROM Posts p
            WHERE p.ParentId IN (SELECT uat_inner.PostId FROM UserActivityTimeline uat_inner WHERE uat_inner.UserId = uem.UserId)
            AND p.PostTypeId = 2 -- Answers to this user's questions
        ) AS SumAnswerScoresOnUsersQuestions,
        (
            SELECT AVG(EXTRACT(EPOCH FROM (p.LastEditDate - p.CreationDate)))
            FROM Posts p
            WHERE p.OwnerUserId = uem.UserId AND p.LastEditDate IS NOT NULL AND p.PostTypeId = 1
        ) AS AvgHoursToFirstEditForOwnQuestions
    FROM
        UserEngagementMetrics uem
    LEFT JOIN UserActivityTimeline uat ON uem.UserId = uat.UserId
    LEFT JOIN PostLinks pl ON uat.PostId = pl.PostId -- Posts linked to user's questions
    GROUP BY
        uem.UserId, uem.DisplayName, uem.Reputation, uem.UserProfileViews, uem.UserTotalUpVotes,
        uem.UserTotalDownVotes, uem.TotalPosts, uem.QuestionsAsked, uem.AnswersProvided,
        uem.TotalComments, uem.TotalBadgesEarned, uem.SumPostScores, uem.SumPostViews,
        uem.SelfEditedPostsCount, uem.BountiesStartedCount
),
BadgeAndVoteSummary AS (
    -- CTE 5: Detailed analysis of badges and votes, including NULL handling and specific vote types.
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END), 0) AS AcceptedVotesCount, -- AcceptedByOriginator
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVoteCount,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVoteCount,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END), 0) AS FavoriteCountGiven,
        MIN(b.Date) AS FirstBadgeDate,
        MAX(b.Date) AS LastBadgeDate,
        LAG(b.Date) OVER (PARTITION BY u.Id ORDER BY b.Date) AS PreviousBadgeDate
    FROM
        Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY
        u.Id, b.Date -- Grouping by b.Date for LAG function to work correctly before final aggregate
    ORDER BY u.Id, b.Date -- Important for LAG to work properly
),
UserAggregatedBadgeVote AS (
    -- CTE 6: Final aggregation for badge and vote summary, including the time difference between badges.
    SELECT
        UserId,
        MAX(GoldBadges) AS MaxGoldBadges,
        MAX(SilverBadges) AS MaxSilverBadges,
        MAX(BronzeBadges) AS MaxBronzeBadges,
        MAX(AcceptedVotesCount) AS MaxAcceptedVotesCount,
        MAX(UpVoteCount) AS MaxUpVoteCount,
        MAX(DownVoteCount) AS MaxDownVoteCount,
        MAX(FavoriteCountGiven) AS MaxFavoriteCountGiven,
        MIN(FirstBadgeDate) AS TrueFirstBadgeDate,
        MAX(LastBadgeDate) AS TrueLastBadgeDate,
        AVG(EXTRACT(DAY FROM (BadgeDate - PreviousBadgeDate))) FILTER (WHERE PreviousBadgeDate IS NOT NULL) AS AvgDaysBetweenBadges
    FROM (
        SELECT
            UserId, GoldBadges, SilverBadges, BronzeBadges, AcceptedVotesCount, UpVoteCount, DownVoteCount,
            FavoriteCountGiven, FirstBadgeDate, LastBadgeDate, PreviousBadgeDate,
            Date AS BadgeDate -- To be used in AVG calculation
        FROM BadgeAndVoteSummary
    ) AS sub
    GROUP BY UserId
)
-- Final result: Combines all CTEs to generate a comprehensive user performance report.
-- Includes advanced calculations, conditional logic, and ranking.
SELECT
    ucs.UserId,
    ucs.DisplayName,
    ucs.Reputation,
    ucs.UserProfileViews,
    ucs.TotalPosts,
    ucs.QuestionsAsked,
    ucs.AnswersProvided,
    ucs.TotalComments,
    ucs.SelfEditedPostsCount,
    ucs.SumPostScores,
    ucs.SumPostViews,
    ucs.BountiesStartedCount,
    COALESCE(uabv.MaxGoldBadges, 0) AS GoldBadgesEarned,
    COALESCE(uabv.MaxSilverBadges, 0) AS SilverBadgesEarned,
    COALESCE(uabv.MaxBronzeBadges, 0) AS BronzeBadgesEarned,
    COALESCE(uabv.MaxAcceptedVotesCount, 0) AS AcceptedVotesForUsersContent,
    COALESCE(uabv.MaxUpVoteCount, 0) AS TotalUpVotesGiven,
    COALESCE(uabv.MaxDownVoteCount, 0) AS TotalDownVotesGiven,
    COALESCE(uabv.AvgDaysBetweenBadges, 0) AS AvgDaysToNextBadge,
    COALESCE(ucs.AvgSecondsBetweenPosts / 3600.0, 0) AS AvgHoursBetweenQuestions,
    ucs.HighestPostScore,
    ucs.AcceptedAnswersForTheirQuestions,
    ucs.LinkedDuplicateQuestions,
    COALESCE(ucs.SumAnswerScoresOnUsersQuestions, 0) AS SumAnswersScoreToUserQuestions,
    COALESCE(ucs.AvgHoursToFirstEditForOwnQuestions, 0) AS AvgHoursToFirstEditOnQuestions,
    -- Complex Influence Score calculation based on various weighted metrics
    (
        ucs.Reputation * 0.4
        + ucs.SumPostScores * 0.15
        + ucs.SumPostViews * 0.05
        + (ucs.QuestionsAsked + ucs.AnswersProvided) * 0.1
        + ucs.TotalComments * 0.05
        + COALESCE(uabv.MaxGoldBadges, 0) * 0.1
        + COALESCE(uabv.MaxSilverBadges, 0) * 0.05
        + ucs.SelfEditedPostsCount * 0.05
        - ucs.UserTotalDownVotes * 0.02 -- Penalty for receiving downvotes
    ) AS CalculatedInfluenceScore,
    -- Categorization of users based on their scores and activity
    CASE
        WHEN ucs.Reputation > 100000 AND COALESCE(uabv.MaxGoldBadges, 0) >= 10 THEN 'Legendary Contributor'
        WHEN ucs.Reputation > 50000 AND ucs.QuestionsAsked >= 50 AND ucs.AnswersProvided >= 100 THEN 'Master Explainer'
        WHEN ucs.HighestPostScore > 500 AND COALESCE(uabv.MaxGoldBadges, 0) >= 3 THEN 'High Impact Creator'
        WHEN ucs.TotalPosts > 200 AND ucs.TotalComments > 500 THEN 'Prodigious Participant'
        ELSE 'Active Member'
    END AS UserTierCategory,
    -- Identifies the top tags for the user based on post count
    (
        SELECT
            ARRAY_AGG(tag_name)
        FROM
            (
                SELECT
                    UNNEST(pq.PostTags) AS tag_name,
                    COUNT(pq.PostId) AS tag_post_count
                FROM PostQualityIndicators pq
                WHERE pq.OwnerUserId = ucs.UserId
                GROUP BY UNNEST(pq.PostTags)
                ORDER BY tag_post_count DESC, tag_name ASC
                LIMIT 5
            ) AS user_top_tags
    ) AS Top5ContributedTags,
    -- Check if the user has a post with a high rank in its category
    (
        SELECT EXISTS (
            SELECT 1 FROM UserActivityTimeline uat_exist
            WHERE uat_exist.UserId = ucs.UserId AND uat_exist.RankByScoreForUser = 1 AND uat_exist.PostSequenceNum <= 5
        )
    ) AS HasEarlyTopPost,
    -- Compare reputation with the user ranked immediately higher by CalculatedInfluenceScore
    LAG(ucs.Reputation, 1, 0) OVER (ORDER BY (
        ucs.Reputation * 0.4
        + ucs.SumPostScores * 0.15
        + ucs.SumPostViews * 0.05
        + (ucs.QuestionsAsked + ucs.AnswersProvided) * 0.1
        + ucs.TotalComments * 0.05
        + COALESCE(uabv.MaxGoldBadges, 0) * 0.1
        + COALESCE(uabv.MaxSilverBadges, 0) * 0.05
        + ucs.SelfEditedPostsCount * 0.05
        - ucs.UserTotalDownVotes * 0.02
    ) DESC) AS ReputationOfHigherRankedUser
FROM
    UserContributionSummary ucs
LEFT JOIN UserAggregatedBadgeVote uabv ON ucs.UserId = uabv.UserId
WHERE
    ucs.TotalPosts > 5 -- Only consider users with meaningful activity
    AND ucs.Reputation > 1000
    AND ucs.QuestionsAsked > 0
    AND (uabv.MaxGoldBadges > 0 OR ucs.SelfEditedPostsCount > 5) -- Filter for impactful or dedicated users
ORDER BY
    CalculatedInfluenceScore DESC, ucs.Reputation DESC
LIMIT 1000;
