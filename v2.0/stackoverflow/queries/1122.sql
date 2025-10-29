-- {"query": "1122.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3930}
WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.UpVotes,
        u.DownVotes,
        u.Views AS ProfileViews,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScore,
        SUM(COALESCE(p.ViewCount, 0)) AS TotalPostViewCount,
        SUM(COALESCE(p.CommentCount, 0)) AS TotalPostCommentCount,
        SUM(COALESCE(p.FavoriteCount, 0)) AS TotalPostFavoriteCount,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        MAX(p.CreationDate) AS LatestPostDate,
        MAX(c.CreationDate) AS LatestCommentDate,
        NTILE(10) OVER (ORDER BY u.Reputation DESC, u.UpVotes DESC, u.LastAccessDate DESC) AS ReputationTier
    FROM Users AS u
    LEFT JOIN Posts AS p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments AS c ON u.Id = c.UserId
    WHERE u.CreationDate >= TIMESTAMP '2015-01-01'
      AND u.DisplayName IS NOT NULL
      AND u.Reputation > 100
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
        u.UpVotes, u.DownVotes, u.Views
),
PostDetails AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.AnswerCount AS PostAnswerCount,
        p.CommentCount AS PostCommentCount,
        p.FavoriteCount AS PostFavoriteCount,
        p.ClosedDate,
        p.CommunityOwnedDate,
        p.LastEditDate,
        p.LastActivityDate,
        p.Title,
        p.Tags,
        COALESCE(EXTRACT(EPOCH FROM (p.ClosedDate - p.CreationDate)) / 3600, 0) AS HoursToClose,
        CASE
            WHEN p.Tags IS NULL OR p.Tags = '' THEN CAST(NULL AS text[])
            ELSE (
                SELECT array_agg(tag) FROM (
                    SELECT regexp_split_to_table(substring(p.Tags FROM 2 FOR (char_length(p.Tags)-2)), '><') AS tag
                ) t
            )
        END AS TagArray,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'CommunityOwned'
            WHEN p.AnswerCount = 0 AND p.PostTypeId = 1 AND p.LastActivityDate < (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '6 months') THEN 'StaleQuestion'
            ELSE 'Active'
        END AS PostStatus
    FROM Posts AS p
    WHERE p.OwnerUserId IS NOT NULL
      AND p.CreationDate >= TIMESTAMP '2015-01-01'
),
PostHistorySummary AS (
    SELECT
        ph.PostId,
        ph.UserId AS EditorUserId,
        ph.CreationDate AS HistoryDate,
        ph.PostHistoryTypeId,
        ph.Text AS HistoryText,
        ph.Comment AS HistoryComment,
        LAG(ph.PostHistoryTypeId, 1, 0) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PrevHistoryType,
        LEAD(ph.PostHistoryTypeId, 1, 0) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS NextHistoryType,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn_latest_history,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 END) OVER (PARTITION BY ph.PostId) AS EditCount,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate ELSE NULL END) OVER (PARTITION BY ph.PostId) AS LastCloseDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate ELSE NULL END) OVER (PARTITION BY ph.PostId) AS LastReopenDate
    FROM PostHistory AS ph
    WHERE ph.CreationDate >= TIMESTAMP '2015-01-01'
),
AggregatedPostHistory AS (
    SELECT
        ph.PostId,
        MAX(ph.LastCloseDate) AS PostLastCloseDate,
        MAX(ph.LastReopenDate) AS PostLastReopenDate,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId = 12 THEN 1 ELSE 0 END) AS DeleteEvents,
        SUM(CASE WHEN ph.PrevHistoryType = 10 AND ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ImmediatelyReopened,
        MAX(ph.EditCount) AS TotalEditsByPost
    FROM PostHistorySummary AS ph
    GROUP BY ph.PostId
),
PostVotesAndLinks AS (
    SELECT
        p.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        SUM(CASE WHEN v.VoteTypeId IN (4, 12) THEN 1 ELSE 0 END) AS FlagVotesReceived,
        COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 1 THEN pl.RelatedPostId END) AS LinkedPostsCount,
        COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.RelatedPostId END) AS DuplicateOfCount
    FROM PostDetails AS p
    LEFT JOIN Votes AS v ON p.PostId = v.PostId
    LEFT JOIN PostLinks AS pl ON p.PostId = pl.PostId
    GROUP BY p.PostId
),
UserTagPerformance AS (
    SELECT
        pd.OwnerUserId AS UserId,
        tag_unnest.Tag AS TagName,
        COUNT(DISTINCT pd.PostId) AS PostsInTag,
        AVG(pd.PostScore) AS AvgPostScoreInTag,
        AVG(pd.PostViewCount) AS AvgPostViewCountInTag,
        SUM(CASE WHEN pd.PostStatus = 'Closed' THEN 1 ELSE 0 END) AS ClosedPostsInTag,
        SUM(CASE WHEN pd.PostStatus = 'StaleQuestion' THEN 1 ELSE 0 END) AS StaleQuestionsInTag
    FROM PostDetails AS pd,
    LATERAL (SELECT unnest(pd.TagArray) AS Tag) AS tag_unnest
    WHERE pd.PostTypeId = 1
    GROUP BY pd.OwnerUserId, tag_unnest.Tag
),
UserBadgeSummary AS (
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        SUM(CASE WHEN b.TagBased = TRUE THEN 1 ELSE 0 END) AS TagBadges,
        MAX(b.Date) AS LatestBadgeDate
    FROM Badges AS b
    WHERE b.Date >= TIMESTAMP '2015-01-01'
    GROUP BY b.UserId
),
CommentSentiment AS (
    SELECT
        c.PostId,
        c.UserId AS CommenterId,
        c.Text AS CommentText,
        c.CreationDate AS CommentCreationDate,
        CASE
            WHEN LOWER(c.Text) LIKE '%thanks%' OR LOWER(c.Text) LIKE '%helpful%' OR LOWER(c.Text) LIKE '%great%' THEN 'Positive'
            WHEN LOWER(c.Text) LIKE '%duplicate%' OR LOWER(c.Text) LIKE '%not clear%' OR LOWER(c.Text) LIKE '%downvote%' OR LOWER(c.Text) LIKE '%unnecessary%' THEN 'Negative'
            ELSE 'Neutral'
        END AS Sentiment,
        ROW_NUMBER() OVER (PARTITION BY c.PostId ORDER BY c.CreationDate DESC) AS rn
    FROM Comments AS c
    WHERE c.CreationDate >= TIMESTAMP '2015-01-01'
),
ProblematicPosts AS (
    SELECT
        pd.PostId,
        pd.OwnerUserId AS UserId,
        pd.PostScore,
        'HighlyDownvotedOrFlagged' AS ProblemType,
        COALESCE(pv.DownVotesReceived, 0) AS RelevantMetric
    FROM PostDetails AS pd
    INNER JOIN PostVotesAndLinks AS pv ON pd.PostId = pv.PostId
    WHERE (pv.DownVotesReceived > 5 OR pv.FlagVotesReceived > 1)
      AND pd.OwnerUserId IS NOT NULL

    UNION ALL

    SELECT
        pd.PostId,
        pd.OwnerUserId AS UserId,
        pd.PostScore,
        'ClosedOrDeleted' AS ProblemType,
        COALESCE(aph.CloseEvents, 0) + COALESCE(aph.DeleteEvents, 0) AS RelevantMetric
    FROM PostDetails AS pd
    INNER JOIN AggregatedPostHistory AS aph ON pd.PostId = aph.PostId
    WHERE pd.OwnerUserId IS NOT NULL
      AND (
            (aph.CloseEvents > 0 AND (aph.ReopenEvents IS NULL OR aph.ReopenEvents = 0 OR aph.PostLastReopenDate < aph.PostLastCloseDate))
            OR aph.DeleteEvents > 0
          )
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.ReputationTier,
    ua.TotalPosts,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.TotalPostScore,
    ua.TotalPostViewCount,
    ua.TotalCommentsMade,
    (
        ua.Reputation * 0.1
        + ua.UpVotes * 0.5
        + ua.DownVotes * -0.2
        + ua.ProfileViews * 0.01
        + ua.TotalPosts * 2
        + ua.TotalCommentsMade * 0.5
        + COALESCE(ubs.GoldBadges, 0) * 10
        + COALESCE(ubs.SilverBadges, 0) * 5
        + COALESCE(ubs.BronzeBadges, 0) * 1
    ) AS UserEngagementScore,
    EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - GREATEST(ua.LastAccessDate, COALESCE(ua.LatestPostDate, TIMESTAMP '2000-01-01'), COALESCE(ua.LatestCommentDate, TIMESTAMP '2000-01-01')))) / (60 * 60 * 24) AS DaysSinceLastActivity,
    COALESCE(SUM(aph.CloseEvents), 0) AS TotalCloseEventsOnPosts,
    COALESCE(SUM(aph.ReopenEvents), 0) AS TotalReopenEventsOnPosts,
    COALESCE(SUM(aph.DeleteEvents), 0) AS TotalDeleteEventsOnPosts,
    COALESCE(SUM(aph.ImmediatelyReopened), 0) AS TotalImmediatelyReopenedPosts,
    COALESCE(SUM(pv.FlagVotesReceived), 0) AS TotalFlagVotesOnPosts,
    COALESCE(AVG(CASE WHEN pd.PostTypeId = 1 THEN pd.HoursToClose ELSE NULL END), 0) AS AvgHoursToCloseOwnQuestions,
    (
        SELECT utp.TagName
        FROM UserTagPerformance AS utp
        WHERE utp.UserId = ua.UserId
        ORDER BY utp.PostsInTag DESC, utp.AvgPostScoreInTag DESC
        LIMIT 1
    ) AS MostFrequentTag,
    COALESCE(AVG(pd.PostScore), 0) AS AvgPostScore,
    CAST(COALESCE(SUM(CASE WHEN pd.PostTypeId = 1 AND pd.PostStatus IN ('Closed', 'StaleQuestion') THEN 1 ELSE 0 END), 0) AS DECIMAL) / NULLIF(ua.QuestionCount, 0) AS ClosedStaleQuestionRatio,
    (
        SELECT cs.CommentText
        FROM CommentSentiment AS cs
        INNER JOIN PostDetails AS p_inner ON cs.PostId = p_inner.PostId
        WHERE p_inner.OwnerUserId = ua.UserId
          AND cs.Sentiment = 'Negative'
          AND cs.rn = 1
        ORDER BY cs.CommentCreationDate DESC
        LIMIT 1
    ) AS LatestNegativeComment,
    ubs.TotalBadges,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.TagBadges,
    COALESCE(COUNT(DISTINCT pp.PostId), 0) AS TotalProblematicPosts,
    COALESCE(SUM(CASE WHEN pp.ProblemType = 'HighlyDownvotedOrFlagged' THEN 1 ELSE 0 END), 0) AS HighlyDownvotedOrFlaggedPosts,
    COALESCE(SUM(CASE WHEN pp.ProblemType = 'ClosedOrDeleted' THEN 1 ELSE 0 END), 0) AS ClosedOrDeletedPosts,
    RANK() OVER (ORDER BY (
        ua.Reputation * 0.1
        + ua.UpVotes * 0.5
        + ua.DownVotes * -0.2
        + ua.ProfileViews * 0.01
        + ua.TotalPosts * 2
        + ua.TotalCommentsMade * 0.5
        + COALESCE(ubs.GoldBadges, 0) * 10
        + COALESCE(ubs.SilverBadges, 0) * 5
        + COALESCE(ubs.BronzeBadges, 0) * 1
        - COALESCE(COUNT(DISTINCT pp.PostId), 0) * 5
    ) DESC) AS OverallEngagementRank
FROM UserActivity AS ua
LEFT JOIN PostDetails AS pd ON ua.UserId = pd.OwnerUserId
LEFT JOIN AggregatedPostHistory AS aph ON pd.PostId = aph.PostId
LEFT JOIN PostVotesAndLinks AS pv ON pd.PostId = pv.PostId
LEFT JOIN UserBadgeSummary AS ubs ON ua.UserId = ubs.UserId
LEFT JOIN ProblematicPosts AS pp ON ua.UserId = pp.UserId
GROUP BY
    ua.UserId, ua.DisplayName, ua.Reputation, ua.ReputationTier,
    ua.TotalPosts, ua.QuestionCount, ua.AnswerCount, ua.TotalPostScore,
    ua.TotalPostViewCount, ua.TotalCommentsMade, ua.UpVotes, ua.DownVotes,
    ua.ProfileViews, ua.LastAccessDate, ua.LatestPostDate, ua.LatestCommentDate,
    ubs.TotalBadges, ubs.GoldBadges, ubs.SilverBadges, ubs.BronzeBadges, ubs.TagBadges
HAVING
    ua.Reputation > 500
    AND (
        COALESCE(SUM(aph.CloseEvents), 0) > 0
        OR COALESCE(SUM(pv.FlagVotesReceived), 0) > 0
        OR ua.QuestionCount > 10
        OR COALESCE(COUNT(DISTINCT pp.PostId), 0) > 0
    )
ORDER BY OverallEngagementRank ASC, DaysSinceLastActivity ASC
LIMIT 100;