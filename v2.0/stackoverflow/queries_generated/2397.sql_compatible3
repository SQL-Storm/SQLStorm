WITH RECURSIVE RecursiveTagHierarchy AS (
    SELECT t.Id, t.TagName, t.ExcerptPostId, t.WikiPostId, 1 AS Level
    FROM Tags t
    WHERE t.IsModeratorOnly = false AND t.IsRequired = false

    UNION ALL

    SELECT t2.Id, t2.TagName, t2.ExcerptPostId, t2.WikiPostId, r.Level + 1
    FROM Tags t2
    JOIN RecursiveTagHierarchy r ON t2.Id > r.Id
    WHERE t2.IsModeratorOnly = false AND t2.IsRequired = false AND r.Level < 3
), QuestionAnswerAggregates AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate,
        q.OwnerUserId,
        count(a.Id) AS TotalAnswers,
        max(a.Score) AS MaxAnswerScore,
        avg(coalesce(a.Score, 0)) AS AvgAnswerScore,
        count(distinct case when v.VoteTypeId = 2 then v.UserId end) AS UpVotesCount,
        count(distinct c.Id) AS CommentCountTotal,
        count(distinct case when pb.PostHistoryTypeId = 10 then pb.Id end) AS CloseVotesCount,
        q.Score
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    LEFT JOIN Votes v ON v.PostId = q.Id
    LEFT JOIN Comments c ON c.PostId = q.Id
    LEFT JOIN PostHistory pb ON pb.PostId = q.Id
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.Title, q.CreationDate, q.OwnerUserId, q.Score
), UserReputationStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreation,
        count(case when b.Class = 1 then b.Id end) AS GoldBadges,
        count(case when b.Class = 2 then b.Id end) AS SilverBadges,
        count(case when b.Class = 3 then b.Id end) AS BronzeBadges,
        rank() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
        rank() OVER (ORDER BY (count(case when b.Class = 1 then b.Id end) * 3 + count(case when b.Class = 2 then b.Id end) * 2 + count(case when b.Class = 3 then b.Id end)) DESC) AS BadgeRank
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
), PostsWithLinkInfo AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        p.PostTypeId,
        count(case when lt.Name = 'Duplicate' then pl.Id end) AS NumDuplicateLinks,
        count(case when lt.Name = 'Linked' then pl.Id end) AS NumLinkedPosts,
        count(pl.Id) AS TotalLinks
    FROM Posts p
    LEFT JOIN PostLinks pl ON pl.PostId = p.Id
    LEFT JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    GROUP BY p.Id, p.Title, p.OwnerUserId, p.PostTypeId
), LatestPostHistoryPerPost AS (
    SELECT ph.PostId,
        ph.Id AS PostHistoryId,
        ph.PostHistoryTypeId,
        ph.CreationDate AS HistoryDate,
        ph.UserId,
        ph.UserDisplayName,
        ph.Comment,
        ph.Text
    FROM (
        SELECT ph.*,
            row_number() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
        FROM PostHistory ph
    ) ph
    WHERE ph.rn = 1
), ComplexFilteredPosts AS (
    SELECT 
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        (SELECT count(*) FROM Comments c WHERE c.PostId = p.Id AND c.CreationDate > p.CreationDate - INTERVAL '30 days') AS RecentCommentsCount,
        (SELECT count(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2 AND v.CreationDate > p.CreationDate - INTERVAL '30 days') AS RecentUpvotes,
        row_number() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS RnkByUserScore
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND (p.Tags ILIKE '%<sql>%' OR p.Tags ILIKE '%<database>%')
      AND p.Score > 0
      AND p.ViewCount > 1000
), UnifiedUserActivity AS (
    SELECT u.Id AS UserId, u.DisplayName, 'Post' AS ActivityType, p.CreationDate AS ActivityDate
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE p.CreationDate > u.CreationDate + INTERVAL '30 days'

    UNION ALL

    SELECT u.Id, u.DisplayName, 'Comment', c.CreationDate
    FROM Users u
    JOIN Comments c ON c.UserId = u.Id
    WHERE c.CreationDate > u.CreationDate + INTERVAL '30 days'

    UNION ALL

    SELECT u.Id, u.DisplayName, 'Badge', b.Date
    FROM Users u
    JOIN Badges b ON b.UserId = u.Id
    WHERE b.Date > u.CreationDate + INTERVAL '30 days'
), UserActivityRanks AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.ActivityType,
        ua.ActivityDate,
        row_number() OVER (PARTITION BY ua.UserId, ua.ActivityType ORDER BY ua.ActivityDate) AS ActivityRowNum
    FROM UnifiedUserActivity ua
), ActivityIntervals AS (
    -- compute intervals by first computing lead per row, then aggregating in an outer query to avoid aggregates over window funcs
    SELECT
        uar.UserId,
        uar.ActivityType,
        avg(uar.IntervalSeconds) * INTERVAL '1 second' AS AvgInterval
    FROM (
        SELECT
            UserId,
            ActivityType,
            ActivityDate,
            lead(ActivityDate) OVER (PARTITION BY UserId, ActivityType ORDER BY ActivityDate) AS NextActivityDate,
            extract(epoch FROM (lead(ActivityDate) OVER (PARTITION BY UserId, ActivityType ORDER BY ActivityDate) - ActivityDate)) AS IntervalSeconds
        FROM UserActivityRanks
    ) uar
    WHERE uar.NextActivityDate IS NOT NULL
    GROUP BY uar.UserId, uar.ActivityType
), ConsolidatedUserStats AS (
    SELECT 
        urs.UserId,
        urs.DisplayName,
        urs.Reputation,
        urs.GoldBadges,
        urs.SilverBadges,
        urs.BronzeBadges,
        coalesce(ai_post.AvgInterval, INTERVAL '0') AS AvgPostInterval,
        coalesce(ai_comment.AvgInterval, INTERVAL '0') AS AvgCommentInterval,
        coalesce(ai_badge.AvgInterval, INTERVAL '0') AS AvgBadgeInterval
    FROM UserReputationStats urs
    LEFT JOIN ActivityIntervals ai_post ON ai_post.UserId = urs.UserId AND ai_post.ActivityType = 'Post'
    LEFT JOIN ActivityIntervals ai_comment ON ai_comment.UserId = urs.UserId AND ai_comment.ActivityType = 'Comment'
    LEFT JOIN ActivityIntervals ai_badge ON ai_badge.UserId = urs.UserId AND ai_badge.ActivityType = 'Badge'
)
SELECT 
    qqa.QuestionId,
    qqa.Title AS QuestionTitle,
    concat_ws(' | ', 
        'Score: ' || qqa.Score,
        'Answers: ' || qqa.TotalAnswers,
        'Max Answer Score: ' || coalesce(qqa.MaxAnswerScore, 0),
        'Avg Answer Score: ' || round(qqa.AvgAnswerScore::numeric,2),
        'Comments: ' || qqa.CommentCountTotal,
        'Close Votes: ' || qqa.CloseVotesCount
    ) AS QuestionStats,
    urs.DisplayName AS OwnerDisplayName,
    urs.Reputation AS OwnerReputation,
    urs.GoldBadges,
    urs.SilverBadges,
    urs.BronzeBadges,
    pwi.NumDuplicateLinks,
    pwi.NumLinkedPosts,
    lph.PostHistoryTypeId,
    lph.Comment AS LastHistoryComment,
    coalesce(cfp.RecentUpvotes, 0) AS RecentUpvotesLast30Days,
    cfp.RecentCommentsCount,
    cu.AvgPostInterval,
    cu.AvgCommentInterval,
    cu.AvgBadgeInterval
FROM QuestionAnswerAggregates qqa
JOIN PostsWithLinkInfo pwi ON pwi.PostId = qqa.QuestionId
LEFT JOIN LatestPostHistoryPerPost lph ON lph.PostId = qqa.QuestionId
LEFT JOIN ComplexFilteredPosts cfp ON cfp.Id = qqa.QuestionId
LEFT JOIN ConsolidatedUserStats cu ON cu.UserId = qqa.OwnerUserId
LEFT JOIN UserReputationStats urs ON urs.UserId = qqa.OwnerUserId
WHERE
    (pwi.NumDuplicateLinks > 0 OR lph.PostHistoryTypeId = 10)
    AND qqa.TotalAnswers > 2
    AND (coalesce(cu.GoldBadges,0) + coalesce(cu.SilverBadges,0) + coalesce(cu.BronzeBadges,0)) > 5
ORDER BY qqa.TotalAnswers DESC, cu.Reputation DESC
LIMIT 50;