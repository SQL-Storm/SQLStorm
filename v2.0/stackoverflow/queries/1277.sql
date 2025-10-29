WITH UserEngagementSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS TotalPostsContributed,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersProvided,
        COALESCE(SUM(p.ViewCount), 0) AS AggregatePostViews,
        COALESCE(SUM(p.Score), 0) AS AggregatePostScore,
        COALESCE(SUM(p.FavoriteCount), 0) AS AggregatePostFavorites,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        COALESCE(SUM(c.Score), 0) AS AggregateCommentScore,
        EXTRACT(EPOCH FROM (u.LastAccessDate - u.CreationDate)) / 86400.0 AS AccountAgeDays,
        (u.UpVotes - u.DownVotes) AS NetVotesGivenReceived
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.UpVotes, u.DownVotes
),
UserBadgeAchievements AS (
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadgesEarned,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        SUM(CASE WHEN b.TagBased = TRUE THEN 1 ELSE 0 END) AS TagBasedBadges,
        MAX(b.Date) AS LatestBadgeAwardDate
    FROM Badges b
    GROUP BY b.UserId
),
PostVersionHistoryAnalysis AS (
    SELECT
        ph.PostId,
        COUNT(ph.Id) AS TotalHistoryEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS PostClosureCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS PostReopenCount,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS PostEditCount,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate ELSE NULL END) AS LastClosedDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate ELSE NULL END) AS LastReopenedDate,
        AVG(edit_interval_seconds) AS AvgDaysBetweenConsecutiveEdits
    FROM (
        SELECT
            ph.PostId,
            ph.Id,
            ph.PostHistoryTypeId,
            ph.CreationDate,
            EXTRACT(EPOCH FROM (ph.CreationDate - LAG(ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate))) AS edit_interval_seconds,
            LAG(ph.PostHistoryTypeId) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS prev_type
        FROM PostHistory ph
    ) ph
    WHERE edit_interval_seconds IS NOT NULL AND ph.PostHistoryTypeId IN (4,5,6) AND ph.prev_type IN (4,5,6)
    GROUP BY ph.PostId
),
DetailedPostAttributes AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.Title,
        p.Body,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        pva.TotalHistoryEvents,
        pva.PostClosureCount,
        pva.PostReopenCount,
        pva.PostEditCount,
        (CASE WHEN pva.AvgDaysBetweenConsecutiveEdits IS NOT NULL THEN pva.AvgDaysBetweenConsecutiveEdits / 86400.0 ELSE NULL END) AS AvgDaysBetweenConsecutiveEdits,
        COALESCE(SUM(CASE WHEN lt.Name = 'Linked' THEN 1 ELSE 0 END), 0) AS LinkedPostReferences,
        COALESCE(SUM(CASE WHEN lt.Name = 'Duplicate' THEN 1 ELSE 0 END), 0) AS DuplicatePostReferences,
        (SELECT COUNT(DISTINCT c_sub.UserId) FROM Comments c_sub WHERE c_sub.PostId = p.Id AND c_sub.UserId IS NOT NULL) AS DistinctCommenters,
        (LENGTH(p.Body) - LENGTH(REPLACE(p.Body, ' ', '')) + 1) AS BodyWordCount,
        NULLIF(TRIM(BOTH ' ' FROM REPLACE(REPLACE(REPLACE(p.Tags, '><', ', '), '<', ''), '>', '')), '') AS FormattedTags,
        owner_avg_bounty.AverageBountyOnOwnerPosts,
        owner_latest_activity.OwnerLatestActivityAcrossPosts
    FROM Posts p
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId
    LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    LEFT JOIN PostVersionHistoryAnalysis pva ON p.Id = pva.PostId
    LEFT JOIN (
        SELECT p2.OwnerUserId, AVG(v.BountyAmount) AS AverageBountyOnOwnerPosts
        FROM Votes v
        JOIN Posts p2 ON v.PostId = p2.Id
        WHERE v.VoteTypeId = 8
        GROUP BY p2.OwnerUserId
    ) vb ON p.OwnerUserId = vb.OwnerUserId
    LEFT JOIN (
        SELECT p3.OwnerUserId, MAX(p3.LastActivityDate) AS OwnerLatestActivityAcrossPosts
        FROM Posts p3
        GROUP BY p3.OwnerUserId
    ) owner_latest_activity ON p.OwnerUserId = owner_latest_activity.OwnerUserId
    LEFT JOIN (
        SELECT p4.OwnerUserId, AVG(v4.BountyAmount) AS AverageBountyOnOwnerPosts
        FROM Posts p4
        LEFT JOIN Votes v4 ON p4.Id = v4.PostId AND v4.VoteTypeId = 8
        GROUP BY p4.OwnerUserId
    ) owner_avg_bounty ON p.OwnerUserId = owner_avg_bounty.OwnerUserId
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY
        p.Id, p.OwnerUserId, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.Title, p.Body, p.Tags, p.AnswerCount, p.CommentCount,
        pva.TotalHistoryEvents, pva.PostClosureCount, pva.PostReopenCount, pva.PostEditCount, pva.AvgDaysBetweenConsecutiveEdits,
        owner_avg_bounty.AverageBountyOnOwnerPosts, owner_latest_activity.OwnerLatestActivityAcrossPosts
    HAVING COUNT(pl.Id) > 0 OR p.CommentCount > 0 OR p.Score > 0
),
RecentHighImpactPosts AS (
    SELECT
        'Question' AS PostCategory,
        dpa.PostId,
        dpa.Title,
        dpa.OwnerUserId,
        dpa.PostCreationDate,
        dpa.PostScore,
        dpa.ViewCount,
        dpa.CommentCount,
        dpa.AnswerCount,
        dpa.LinkedPostReferences,
        RANK() OVER (ORDER BY dpa.PostScore DESC, dpa.ViewCount DESC, dpa.PostCreationDate DESC) AS PostEngagementRank
    FROM DetailedPostAttributes dpa
    WHERE dpa.PostTypeId = 1
      AND dpa.PostCreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
      AND dpa.PostScore > 5
    UNION ALL
    SELECT
        'Answer' AS PostCategory,
        dpa.PostId,
        dpa.Title,
        dpa.OwnerUserId,
        dpa.PostCreationDate,
        dpa.PostScore,
        dpa.ViewCount,
        dpa.CommentCount,
        NULL AS AnswerCount,
        dpa.LinkedPostReferences,
        RANK() OVER (ORDER BY dpa.PostScore DESC, dpa.CommentCount DESC, dpa.PostCreationDate DESC) AS PostEngagementRank
    FROM DetailedPostAttributes dpa
    WHERE dpa.PostTypeId = 2
      AND dpa.PostCreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months'
      AND dpa.PostScore > 3
)
SELECT
    ues.UserId,
    ues.DisplayName,
    ues.Reputation,
    ues.AccountAgeDays,
    ues.TotalPostsContributed,
    ues.QuestionsAsked,
    ues.AnswersProvided,
    ues.AggregatePostViews,
    ues.AggregatePostScore,
    ues.TotalCommentsMade,
    COALESCE(uba.GoldBadges, 0) AS GoldBadges,
    COALESCE(uba.SilverBadges, 0) AS SilverBadges,
    COALESCE(uba.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(uba.TagBasedBadges, 0) AS TagBasedBadges,
    COALESCE(uba.LatestBadgeAwardDate, ues.UserCreationDate) AS EffectiveLatestUserActivityDate,
    (ues.Reputation * 0.15 + ues.AggregatePostScore * 0.4 + ues.AggregatePostViews * 0.005 + ues.TotalCommentsMade * 0.1 + COALESCE(uba.GoldBadges, 0) * 8 + COALESCE(uba.TagBasedBadges, 0) * 2 + ues.NetVotesGivenReceived * 0.01) AS OverallUserInfluenceScore,
    AVG(dpa.DistinctCommenters) FILTER (WHERE dpa.OwnerUserId = ues.UserId) AS AvgDistinctCommentersPerOwnedPost,
    (SUM(CASE WHEN dpa.PostEditCount > 2 THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(dpa.PostId), 0)) AS PctPostsMultiEdited,
    EXISTS (
        SELECT 1
        FROM Badges b_corr
        JOIN Tags t_corr ON LOWER(b_corr.Name) = LOWER(t_corr.TagName)
        WHERE b_corr.UserId = ues.UserId
          AND b_corr.Class = 1
          AND EXISTS (
              SELECT 1
              FROM DetailedPostAttributes dpa_corr
              WHERE dpa_corr.OwnerUserId = ues.UserId
                AND dpa_corr.FormattedTags LIKE '%' || t_corr.TagName || '%'
                AND dpa_corr.PostCreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '3 years'
          )
    ) AS HasGoldBadgeForOwnActiveTag,
    RANK() OVER (PARTITION BY (
        CASE
            WHEN ues.Reputation >= 50000 THEN 'Elite'
            WHEN ues.Reputation >= 10000 THEN 'HighTier'
            WHEN ues.Reputation >= 1000 THEN 'MidTier'
            ELSE 'LowTier'
        END
    ) ORDER BY (ues.Reputation * 0.15 + ues.AggregatePostScore * 0.4 + ues.AggregatePostViews * 0.005 + ues.TotalCommentsMade * 0.1 + COALESCE(uba.GoldBadges, 0) * 8 + COALESCE(uba.TagBasedBadges, 0) * 2 + ues.NetVotesGivenReceived * 0.01) DESC) AS ReputationTierInfluenceRank,
    CASE
        WHEN ues.QuestionsAsked > ues.AnswersProvided AND ues.QuestionsAsked > 0 THEN 'Primary Questioner'
        WHEN ues.AnswersProvided > ues.QuestionsAsked AND ues.AnswersProvided > 0 THEN 'Primary Answerer'
        WHEN ues.TotalPostsContributed > 0 THEN 'Balanced Contributor'
        WHEN ues.TotalCommentsMade > 0 THEN 'Commentator Only'
        ELSE 'Passive User'
    END AS UserPrimaryContributionRole,
    UPPER(SUBSTRING(ues.DisplayName FROM 1 FOR 7)) AS DisplayNamePrefix,
    (CASE WHEN Users.AboutMe LIKE '%SQL%' OR Users.AboutMe LIKE '%database%' OR Users.AboutMe LIKE '%developer%' THEN TRUE ELSE FALSE END) AS IsTechnicalBio,
    MAX(CASE WHEN rhip.PostCategory = 'Question' AND rhip.PostEngagementRank <= 10 THEN rhip.Title ELSE NULL END) AS Top10RecentQuestionTitle,
    MAX(CASE WHEN rhip.PostCategory = 'Answer' AND rhip.PostEngagementRank <= 10 THEN rhip.Title ELSE NULL END) AS Top10RecentAnswerTitle,
    SUM(CASE WHEN rhip.PostCategory = 'Question' THEN 1 ELSE 0 END) AS TotalRecentHighImpactQuestions,
    SUM(CASE WHEN rhip.PostCategory = 'Answer' THEN 1 ELSE 0 END) AS TotalRecentHighImpactAnswers
FROM UserEngagementSummary ues
LEFT JOIN UserBadgeAchievements uba ON ues.UserId = uba.UserId
LEFT JOIN DetailedPostAttributes dpa ON ues.UserId = dpa.OwnerUserId
LEFT JOIN RecentHighImpactPosts rhip ON ues.UserId = rhip.OwnerUserId
LEFT JOIN Users ON ues.UserId = Users.Id
WHERE
    ues.Reputation > 500 AND ues.AccountAgeDays > 90
    AND (ues.DisplayName IS NOT NULL AND ues.DisplayName <> '' AND ues.DisplayName NOT LIKE 'user%')
    AND ues.LastAccessDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
GROUP BY
    ues.UserId, ues.DisplayName, ues.Reputation, ues.AccountAgeDays, ues.TotalPostsContributed, ues.QuestionsAsked,
    ues.AnswersProvided, ues.AggregatePostViews, ues.AggregatePostScore, ues.TotalCommentsMade,
    uba.GoldBadges, uba.SilverBadges, uba.BronzeBadges, uba.TagBasedBadges, uba.LatestBadgeAwardDate,
    ues.UserCreationDate, ues.NetVotesGivenReceived, Users.AboutMe
ORDER BY OverallUserInfluenceScore DESC, ues.Reputation DESC
LIMIT 5000;