WITH UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COALESCE(SUM(p.ViewCount), 0) AS TotalPostViews,
        COALESCE(SUM(p.FavoriteCount), 0) AS TotalFavoritesReceived,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COALESCE(SUM(c.Score), 0) AS TotalCommentScore,
        MAX(p.LastActivityDate) AS LastPostActivityDate,
        MAX(c.CreationDate) AS LastCommentActivityDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
UserBadgeAwards AS (
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
PostHistoricalEdits AS (
    SELECT
        ph.PostId,
        COUNT(DISTINCT ph.Id) AS TotalHistoryEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105) THEN 1 ELSE 0 END) AS CloseCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenCount,
        MAX(ph.CreationDate) AS LastHistoryEventDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (1,2,3,4,5,6,10,11,101,102,103,104,105)
    GROUP BY ph.PostId
),
UserPostRankings AS (
    SELECT
        ue.UserId,
        ue.DisplayName,
        ue.Reputation,
        ue.UserCreationDate,
        ue.TotalPosts,
        ue.QuestionCount,
        ue.AnswerCount,
        ue.TotalPostScore,
        ue.TotalPostViews,
        ue.TotalFavoritesReceived,
        ue.TotalComments,
        uba.TotalBadges,
        uba.GoldBadges,
        uba.SilverBadges,
        uba.BronzeBadges,
        RANK() OVER (ORDER BY ue.Reputation DESC, ue.TotalPostScore DESC) AS UserReputationRank,
        NTILE(10) OVER (ORDER BY ue.TotalPosts DESC) AS PostCountDecile,
        AVG(ue.TotalPostScore) OVER (PARTITION BY EXTRACT(MONTH FROM ue.UserCreationDate)) AS AvgScoreForUsersCreatedInMonth,
        LAG(ue.Reputation, 1, 0) OVER (ORDER BY ue.Reputation DESC) AS PrevUserReputation
    FROM UserEngagement ue
    LEFT JOIN UserBadgeAwards uba ON ue.UserId = uba.UserId
    WHERE ue.TotalPosts > 0 OR ue.TotalComments > 0
),
CommentActivitySummary AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS TotalCommentsOnPost,
        MAX(c.CreationDate) AS LatestCommentDate,
        SUM(CASE WHEN c.UserId IS NULL THEN 1 ELSE 0 END) AS AnonymousCommentCount,
        CAST(AVG(c.Score) AS NUMERIC(10,2)) AS AvgCommentScoreForPost
    FROM Comments c
    GROUP BY c.PostId
),
PostLinkAnalysis AS (
    SELECT
        pl.PostId,
        SUM(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS LinkedPostCount,
        SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicatePostCount,
        MAX(pl.CreationDate) AS LastLinkDate
    FROM PostLinks pl
    GROUP BY pl.PostId
),
SpecificPostDetails_Part1 AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.Title,
        p.Tags,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.AcceptedAnswerId,
        p.ParentId,
        ph.EditCount,
        ph.CloseCount,
        ph.ReopenCount,
        (SELECT ph_inner.UserDisplayName
         FROM PostHistory ph_inner
         WHERE ph_inner.PostId = p.Id
           AND ph_inner.PostHistoryTypeId IN (4, 5, 6)
         ORDER BY ph_inner.CreationDate DESC
         LIMIT 1
        ) AS LatestEditorDisplayName,
        COALESCE(UPPER(SUBSTRING(p.Tags FROM 2 FOR (POSITION('>' IN p.Tags) - 2))), 'NO_TAGS_FOUND') AS PrimaryTag,
        CASE
            WHEN p.AcceptedAnswerId IS NOT NULL AND p.PostTypeId = 1 THEN TRUE
            ELSE FALSE
        END AS HasAcceptedAnswer,
        (p.Score * 1.0 / NULLIF(p.ViewCount, 0)) * 100 AS ScorePerViewPercentage,
        DATE_PART('day', CAST('2024-10-01 12:34:56' AS timestamp) - p.CreationDate) AS DaysSinceCreation
    FROM Posts p
    INNER JOIN PostHistoricalEdits ph ON p.Id = ph.PostId
    WHERE p.PostTypeId IN (1, 2)
      AND p.Score > 50
      AND p.ViewCount > 1000
      AND p.CreationDate >= DATE '2020-01-01'
),
SpecificPostDetails_Part2 AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.Title,
        p.Tags,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.AcceptedAnswerId,
        p.ParentId,
        ph.EditCount,
        ph.CloseCount,
        ph.ReopenCount,
        (SELECT ph_inner.UserDisplayName
         FROM PostHistory ph_inner
         WHERE ph_inner.PostId = p.Id
           AND ph_inner.PostHistoryTypeId IN (4, 5, 6)
         ORDER BY ph_inner.CreationDate DESC
         LIMIT 1
        ) AS LatestEditorDisplayName,
        COALESCE(UPPER(SUBSTRING(p.Tags FROM 2 FOR (POSITION('>' IN p.Tags) - 2))), 'NO_TAGS_FOUND') AS PrimaryTag,
        CASE WHEN p.AcceptedAnswerId IS NOT NULL AND p.PostTypeId = 1 THEN TRUE ELSE FALSE END AS HasAcceptedAnswer,
        (p.Score * 1.0 / NULLIF(p.ViewCount, 0)) * 100 AS ScorePerViewPercentage,
        DATE_PART('day', CAST('2024-10-01 12:34:56' AS timestamp) - p.CreationDate) AS DaysSinceCreation
    FROM Posts p
    INNER JOIN PostHistoricalEdits ph ON p.Id = ph.PostId
    WHERE p.PostTypeId = 1
      AND (ph.CloseCount > 0 OR ph.ReopenCount > 0)
      AND p.CreationDate BETWEEN DATE '2019-01-01' AND DATE '2021-12-31'
),
SpecificPostDetails AS (
    SELECT * FROM SpecificPostDetails_Part1
    UNION ALL
    SELECT * FROM SpecificPostDetails_Part2
),
DetailedPostMetrics AS (
    SELECT
        spd.PostId,
        spd.OwnerUserId,
        spd.PostTypeId,
        spd.Title,
        spd.Tags,
        spd.PostCreationDate,
        spd.Score,
        spd.ViewCount,
        spd.AnswerCount,
        spd.CommentCount,
        spd.FavoriteCount,
        spd.AcceptedAnswerId,
        spd.ParentId,
        spd.EditCount,
        spd.CloseCount,
        spd.ReopenCount,
        spd.LatestEditorDisplayName,
        spd.PrimaryTag,
        spd.HasAcceptedAnswer,
        spd.ScorePerViewPercentage,
        spd.DaysSinceCreation,
        cas.TotalCommentsOnPost,
        cas.LatestCommentDate,
        cas.AnonymousCommentCount,
        CASE WHEN cas.TotalCommentsOnPost > 5 THEN cas.AvgCommentScoreForPost ELSE NULL END AS AvgCommentScoreIfManyComments,
        pla.LinkedPostCount,
        pla.DuplicatePostCount,
        pla.LastLinkDate,
        AVG(spd.Score) OVER (PARTITION BY spd.PrimaryTag) AS AvgScoreForPrimaryTag,
        ROW_NUMBER() OVER (PARTITION BY spd.OwnerUserId ORDER BY spd.PostCreationDate DESC) AS PostSequenceByUser
    FROM SpecificPostDetails spd
    LEFT JOIN CommentActivitySummary cas ON spd.PostId = cas.PostId
    LEFT JOIN PostLinkAnalysis pla ON spd.PostId = pla.PostId
)
SELECT
    upr.UserId,
    upr.DisplayName,
    upr.Reputation,
    upr.UserReputationRank,
    upr.PostCountDecile,
    upr.GoldBadges,
    upr.SilverBadges,
    upr.BronzeBadges,
    dpm.PostId,
    dpm.PostTypeId,
    dpm.Title,
    dpm.PrimaryTag,
    dpm.PostCreationDate,
    dpm.Score AS PostScore,
    dpm.ViewCount AS PostViewCount,
    dpm.AnswerCount,
    dpm.FavoriteCount,
    dpm.EditCount AS PostEditCount,
    dpm.CloseCount AS PostCloseCount,
    dpm.ReopenCount AS PostReopenCount,
    dpm.HasAcceptedAnswer,
    dpm.ScorePerViewPercentage,
    dpm.DaysSinceCreation,
    dpm.TotalCommentsOnPost,
    dpm.LatestCommentDate,
    dpm.AnonymousCommentCount,
    dpm.AvgCommentScoreIfManyComments,
    dpm.LinkedPostCount,
    dpm.DuplicatePostCount,
    dpm.AvgScoreForPrimaryTag,
    dpm.PostSequenceByUser,
    COALESCE(dpm.LatestEditorDisplayName, upr.DisplayName, 'Community') AS ActualEditorName,
    CASE
        WHEN upr.Reputation > 5000 AND upr.GoldBadges > 0 AND dpm.ScorePerViewPercentage > 0.5 THEN 'Elite Contributor'
        WHEN upr.Reputation > 1000 AND (upr.SilverBadges > 0 OR upr.BronzeBadges > 5) AND dpm.Score > 50 THEN 'Valuable Contributor'
        WHEN upr.TotalPosts > 50 OR dpm.TotalCommentsOnPost > 10 THEN 'Active User'
        ELSE 'Casual User'
    END AS UserEngagementTier,
    (SELECT COUNT(DISTINCT ph_nested.PostId)
     FROM PostHistory ph_nested
     WHERE ph_nested.UserId = upr.UserId
       AND ph_nested.PostHistoryTypeId = 11
       AND ph_nested.CreationDate >= upr.UserCreationDate
    ) AS UserReopenedPostsCount
FROM UserPostRankings upr
INNER JOIN DetailedPostMetrics dpm ON upr.UserId = dpm.OwnerUserId
WHERE
    upr.Reputation > 500
    AND (dpm.PostTypeId = 1 OR (dpm.PostTypeId = 2 AND dpm.HasAcceptedAnswer IS TRUE))
    AND dpm.Score > 5
    AND dpm.DaysSinceCreation < 365 * 3
    AND dpm.PostSequenceByUser <= 5
    AND (dpm.PrimaryTag = 'SQL' OR dpm.PrimaryTag = 'DATABASE' OR dpm.PrimaryTag LIKE '%SQL%')
    AND (dpm.AvgCommentScoreIfManyComments IS NULL OR dpm.AvgCommentScoreIfManyComments > 1.5)
ORDER BY
    upr.UserReputationRank ASC,
    dpm.Score DESC,
    dpm.DaysSinceCreation ASC
LIMIT 1000;