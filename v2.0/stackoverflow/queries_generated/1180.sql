-- {"query": "1180.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2822} 

WITH UserContentStats AS (
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        COALESCE(AVG(p.Score), 0) AS AvgPostScore,
        EXTRACT(DAY FROM AGE(CURRENT_TIMESTAMP, u.CreationDate)) AS DaysSinceCreation,
        EXTRACT(DAY FROM AGE(CURRENT_TIMESTAMP, MAX(COALESCE(p.LastActivityDate, p.CreationDate, u.CreationDate)))) AS LastActivityRecencyDays
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id, u.CreationDate
),
UserVoteAggregates AS (
    SELECT
        u.Id AS UserId,
        SUM(CASE WHEN v_received.VoteTypeId = 2 THEN 1 ELSE 0 END) AS ReceivedUpvotes,
        SUM(CASE WHEN v_received.VoteTypeId = 3 THEN 1 ELSE 0 END) AS ReceivedDownvotes,
        SUM(CASE WHEN v_given.VoteTypeId = 2 THEN 1 ELSE 0 END) AS GivenUpvotes,
        SUM(CASE WHEN v_given.VoteTypeId = 3 THEN 1 ELSE 0 END) AS GivenDownvotes,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) AND ph.UserId = p.OwnerUserId THEN p.Id END) AS SelfEditedPostsCount,
        SUM(CASE WHEN ph_close.PostHistoryTypeId = 10 AND CAST(ph_close.Comment AS SMALLINT) IN (1, 2, 3, 4, 7, 10, 20, 101, 102, 103, 104, 105) THEN 1 ELSE 0 END) AS PostsClosedByOwnerVoting,
        (SELECT COUNT(DISTINCT v_corr.PostId) FROM Votes v_corr WHERE v_corr.UserId = u.Id AND v_corr.VoteTypeId IN (2,3)) AS TotalPostsVotedOn
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v_received ON p.Id = v_received.PostId -- Votes received on user's posts
    LEFT JOIN Votes v_given ON u.Id = v_given.UserId -- Votes given by the user
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.UserId = p.OwnerUserId
    LEFT JOIN PostHistory ph_close ON p.Id = ph_close.PostId AND ph_close.PostHistoryTypeId = 10 AND ph_close.UserId = u.Id
    GROUP BY u.Id
),
UserBadgeAchievement AS (
    SELECT
        u.Id AS UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MIN(CASE WHEN b.Class = 1 THEN b.Date END) AS EarliestGoldBadgeDate,
        MIN(b.Date) AS FirstEverBadgeDate,
        COUNT(DISTINCT b.Name) AS UniqueBadgeCount
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id
),
PostTagStats AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId AS PostOwnerUserId,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><')) AS TagName
    FROM Posts p
    WHERE p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2 AND p.OwnerUserId IS NOT NULL
),
AggregatedTagImpact AS (
    SELECT
        pts.TagName,
        AVG(pts.PostScore) AS AvgScoreForTag,
        COUNT(pts.PostId) AS TotalPostsForTag,
        DENSE_RANK() OVER (ORDER BY COUNT(pts.PostId) DESC, AVG(pts.PostScore) DESC) AS TagPopularityRank,
        NTILE(10) OVER (ORDER BY AVG(pts.PostScore) DESC) AS ScoreDecile
    FROM PostTagStats pts
    GROUP BY pts.TagName
),
UserTagContributions AS (
    SELECT
        pts.PostOwnerUserId AS UserId,
        pts.TagName,
        COUNT(DISTINCT pts.PostId) AS PostsInTag,
        SUM(pts.PostScore) AS TotalScoreInTag,
        RANK() OVER (PARTITION BY pts.PostOwnerUserId ORDER BY SUM(pts.PostScore) DESC, COUNT(DISTINCT pts.PostId) DESC) AS RankPerUserTagScore
    FROM PostTagStats pts
    GROUP BY pts.PostOwnerUserId, pts.TagName
),
ModerationOverview AS (
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.PostId END) AS TotalPostsClosed,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS LastClosedPostDate,
        COALESCE(NULLIF(
            (SELECT crt.Name
             FROM PostHistory ph_sub
             JOIN CloseReasonTypes crt ON CAST(ph_sub.Comment AS SMALLINT) = crt.Id
             WHERE ph_sub.PostId IN (SELECT p_sub.Id FROM Posts p_sub WHERE p_sub.OwnerUserId = u.Id)
               AND ph_sub.PostHistoryTypeId = 10
             GROUP BY crt.Name
             ORDER BY COUNT(crt.Id) DESC
             LIMIT 1), ''), 'N/A') AS MostFrequentClosureReason,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.PostId END) AS TotalPostsReopened,
        LAG(ph.CreationDate, 1, '1970-01-01'::timestamp) OVER (PARTITION BY u.Id ORDER BY ph.CreationDate) AS PrevHistoryActionDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    GROUP BY u.Id
),
UserCompositeData AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Location,
        u.AboutMe,
        ucs.TotalPosts,
        ucs.TotalQuestions,
        ucs.TotalAnswers,
        ucs.TotalCommentsMade,
        ucs.AvgPostScore,
        ucs.DaysSinceCreation,
        ucs.LastActivityRecencyDays,
        uva.ReceivedUpvotes,
        uva.ReceivedDownvotes,
        uva.GivenUpvotes,
        uva.GivenDownvotes,
        uva.SelfEditedPostsCount,
        uva.PostsClosedByOwnerVoting,
        uva.TotalPostsVotedOn,
        uba.GoldBadges,
        uba.SilverBadges,
        uba.BronzeBadges,
        uba.EarliestGoldBadgeDate,
        uba.FirstEverBadgeDate,
        uba.UniqueBadgeCount,
        mo.TotalPostsClosed,
        mo.LastClosedPostDate,
        mo.MostFrequentClosureReason,
        mo.TotalPostsReopened,
        mo.PrevHistoryActionDate
    FROM Users u
    LEFT JOIN UserContentStats ucs ON u.Id = ucs.UserId
    LEFT JOIN UserVoteAggregates uva ON u.Id = uva.UserId
    LEFT JOIN UserBadgeAchievement uba ON u.Id = uba.UserId
    LEFT JOIN ModerationOverview mo ON u.Id = mo.UserId
    WHERE u.Reputation > 1000
)
SELECT
    ucd.UserId,
    COALESCE(ucd.DisplayName, 'Anonymous' || ucd.UserId) AS UserDisplay,
    ucd.Reputation,
    ucd.TotalPosts,
    ucd.TotalQuestions,
    ucd.TotalAnswers,
    ucd.TotalCommentsMade,
    ucd.AvgPostScore,
    ucd.ReceivedUpvotes,
    ucd.GivenUpvotes,
    ucd.SelfEditedPostsCount,
    ucd.GoldBadges,
    ucd.SilverBadges,
    ucd.BronzeBadges,
    ucd.EarliestGoldBadgeDate,
    ucd.MostFrequentClosureReason,
    ucd.LastClosedPostDate,
    (SELECT COUNT(DISTINCT pl.RelatedPostId) FROM PostLinks pl
     WHERE pl.PostId IN (SELECT p_sub.Id FROM Posts p_sub WHERE p_sub.OwnerUserId = ucd.UserId AND p_sub.PostTypeId = 1)
       AND pl.LinkTypeId = 1) AS TotalLinkedQuestionsBySelf,
    CAST(ucd.ReceivedUpvotes AS DECIMAL) / NULLIF(ucd.TotalPosts * 10, 0) AS UpvoteEfficiencyRatio,
    CASE
        WHEN ucd.Location IS NULL OR LENGTH(TRIM(ucd.Location)) = 0 THEN 'Unknown Location'
        ELSE UPPER(SUBSTRING(ucd.Location, 1, 1)) || LOWER(SUBSTRING(ucd.Location, 2))
    END AS FormattedLocation,
    NTILE(5) OVER (ORDER BY ucd.Reputation DESC, ucd.ReceivedUpvotes DESC) AS ReputationTier,
    LEAD(ucd.Reputation, 1, 0) OVER (ORDER BY ucd.Reputation DESC) AS NextHigherReputation,
    STRING_AGG(DISTINCT utg.TagName, ', ') FILTER (WHERE utg.RankPerUserTagScore <= 3 AND utg.TotalScoreInTag > 100) AS TopTagsByScore,
    COUNT(DISTINCT CASE WHEN ucd.LastActivityRecencyDays < 30 THEN 1 END) OVER (PARTITION BY ucd.Reputation / 10000) AS ActiveUsersInReputationBand
FROM UserCompositeData ucd
LEFT JOIN UserTagContributions utg ON ucd.UserId = utg.UserId
WHERE
    ucd.Reputation > 5000 AND
    ucd.TotalPosts > 100 AND
    ucd.ReceivedUpvotes > 500 AND
    ucd.SelfEditedPostsCount >= 5 AND
    (ucd.GoldBadges >= 1 OR ucd.SilverBadges >= 3) AND
    ucd.LastActivityRecencyDays < 365 AND
    ucd.DaysSinceCreation > 730 AND
    ucd.AvgPostScore > 5 AND
    ucd.MostFrequentClosureReason IS DISTINCT FROM 'Off-topic'
GROUP BY
    ucd.UserId,
    ucd.DisplayName,
    ucd.Reputation,
    ucd.TotalPosts,
    ucd.TotalQuestions,
    ucd.TotalAnswers,
    ucd.TotalCommentsMade,
    ucd.AvgPostScore,
    ucd.ReceivedUpvotes,
    ucd.GivenUpvotes,
    ucd.SelfEditedPostsCount,
    ucd.GoldBadges,
    ucd.SilverBadges,
    ucd.BronzeBadges,
    ucd.EarliestGoldBadgeDate,
    ucd.MostFrequentClosureReason,
    ucd.LastClosedPostDate,
    ucd.Location,
    ucd.LastActivityRecencyDays
HAVING
    COUNT(utg.TagName) >= 1
ORDER BY
    ucd.Reputation DESC, ucd.ReceivedUpvotes DESC
LIMIT 100 OFFSET 10;
