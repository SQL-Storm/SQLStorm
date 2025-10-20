WITH UserCoreStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COALESCE(u.Location, 'N/A') AS UserLocation,
        LENGTH(COALESCE(u.AboutMe, '')) AS AboutMeLength,
        COALESCE(u.Views, 0) AS ProfileViews,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestionsOwned,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswersOwned,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location, u.AboutMe, u.Views
),
PostPerformanceSummary AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.FavoriteCount,
        p.CommentCount,
        p.LastActivityDate,
        p.AcceptedAnswerId,
        p.ParentId,
        p.Title AS PostTitle,
        p.Tags,
        LENGTH(p.Body) AS BodyLength,
        COUNT(DISTINCT ph.Id) AS TotalHistoryEvents,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.Id END) AS EditCount,
        MAX(ph.CreationDate) AS LastHistoryDate,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostScoreByOwner,
        LAG(p.CreationDate, 1, p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostCreationDateByOwner
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    GROUP BY
        p.Id, p.OwnerUserId, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.FavoriteCount,
        p.CommentCount, p.LastActivityDate, p.AcceptedAnswerId, p.ParentId, p.Title, p.Tags, p.Body
),
QuestionTagMetrics_Flat AS (
    -- Use regexp_split_to_table when available; for other dialects this part may need replacement with equivalent split function.
    SELECT
        pps.OwnerUserId AS UserId,
        TRIM(x.tag) AS TagName,
        COUNT(*) AS QuestionsWithTag,
        AVG(pps.PostScore) AS AvgScoreForTag
    FROM PostPerformanceSummary pps,
    LATERAL (
        SELECT
            CASE
                WHEN pps.Tags IS NULL OR LENGTH(pps.Tags) <= 2 THEN NULL
                ELSE regexp_split_to_table(SUBSTRING(pps.Tags FROM 2 FOR LENGTH(pps.Tags) - 2), '><')
            END AS tag
    ) x
    WHERE pps.PostTypeId = 1 AND pps.Tags IS NOT NULL AND LENGTH(pps.Tags) > 2
    GROUP BY pps.OwnerUserId, TRIM(x.tag)
),
UserInfluenceProfile AS (
    SELECT
        ucs.UserId,
        ucs.DisplayName,
        ucs.Reputation,
        ucs.UserCreationDate,
        ucs.LastAccessDate,
        ucs.UserLocation,
        ucs.AboutMeLength,
        ucs.ProfileViews,
        ucs.TotalPostsOwned,
        ucs.TotalQuestionsOwned,
        ucs.TotalAnswersOwned,
        ucs.TotalCommentsMade,
        ucs.GoldBadges,
        ucs.SilverBadges,
        ucs.BronzeBadges,
        AVG(CASE WHEN pps.PostTypeId = 1 THEN pps.PostScore END) AS AvgQuestionScore,
        AVG(CASE WHEN pps.PostTypeId = 2 THEN pps.PostScore END) AS AvgAnswerScore,
        SUM(CASE WHEN pps.PostTypeId = 1 THEN pps.FavoriteCount ELSE 0 END) AS TotalQuestionFavorites,
        SUM(pps.EditCount) AS TotalEditsMade,
        MAX(pps.LastHistoryDate) AS MostRecentEdit,
        (SELECT qtm.TagName
         FROM QuestionTagMetrics_Flat qtm
         WHERE qtm.UserId = ucs.UserId
         ORDER BY qtm.QuestionsWithTag DESC, qtm.AvgScoreForTag DESC
         LIMIT 1) AS MostFrequentTag,
        (SELECT pps_sq.PostScore
         FROM PostPerformanceSummary pps_sq
         WHERE pps_sq.OwnerUserId = ucs.UserId AND pps_sq.PostTypeId = 1
         ORDER BY pps_sq.ViewCount DESC
         LIMIT 1) AS TopQuestionScoreByViews,
        RANK() OVER (ORDER BY ucs.Reputation DESC, ucs.GoldBadges DESC, ucs.TotalPostsOwned DESC) AS GlobalInfluenceRank,
        NTILE(5) OVER (ORDER BY ucs.Reputation DESC) AS ReputationQuintile,
        AVG(ucs.Reputation) OVER (PARTITION BY ucs.UserLocation) AS AvgReputationInLocation,
        CASE
            WHEN ucs.Reputation >= 20000 AND ucs.GoldBadges >= 10 THEN 'Elite Contributor'
            WHEN ucs.Reputation >= 5000 AND ucs.SilverBadges >= 5 THEN 'Key Contributor'
            WHEN ucs.Reputation >= 1000 AND ucs.TotalPostsOwned >= 20 THEN 'Active Member'
            ELSE 'Emerging Member'
        END AS InfluenceTier
    FROM UserCoreStats ucs
    LEFT JOIN PostPerformanceSummary pps ON ucs.UserId = pps.OwnerUserId
    GROUP BY
        ucs.UserId, ucs.DisplayName, ucs.Reputation, ucs.UserCreationDate, ucs.LastAccessDate,
        ucs.UserLocation, ucs.AboutMeLength, ucs.ProfileViews, ucs.TotalPostsOwned,
        ucs.TotalQuestionsOwned, ucs.TotalAnswersOwned, ucs.TotalCommentsMade,
        ucs.GoldBadges, ucs.SilverBadges, ucs.BronzeBadges
),
RecentActivitySummary AS (
    SELECT
        ucs.UserId,
        ucs.DisplayName,
        ucs.Reputation,
        ucs.UserCreationDate,
        ucs.LastAccessDate,
        ucs.UserLocation,
        COUNT(DISTINCT CASE WHEN pps.PostCreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year' THEN pps.PostId END) AS RecentPosts,
        COUNT(DISTINCT CASE WHEN c.CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months' THEN c.Id END) AS RecentComments,
        COUNT(DISTINCT CASE WHEN ph.CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year' AND ph.PostHistoryTypeId IN (4,5,6) THEN ph.Id END) AS RecentEdits,
        AVG(CASE WHEN pps.PostTypeId = 1 AND pps.PostCreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 years' THEN pps.PostScore ELSE NULL END) AS AvgQuestionScoreLast2Years,
        SUM(v.BountyAmount) AS TotalBountyPosted
    FROM UserCoreStats ucs
    LEFT JOIN PostPerformanceSummary pps ON ucs.UserId = pps.OwnerUserId
    LEFT JOIN Comments c ON ucs.UserId = c.UserId
    LEFT JOIN PostHistory ph ON ucs.UserId = ph.UserId
    LEFT JOIN Votes v ON ucs.UserId = v.UserId AND v.VoteTypeId IN (8,9)
    GROUP BY
        ucs.UserId, ucs.DisplayName, ucs.Reputation, ucs.UserCreationDate, ucs.LastAccessDate, ucs.UserLocation
)
SELECT
    uip.UserId,
    uip.DisplayName,
    'High-Influence' AS UserCategory,
    uip.Reputation,
    uip.GlobalInfluenceRank,
    uip.ReputationQuintile,
    uip.InfluenceTier,
    AGE(CAST('2024-10-01 12:34:56' AS timestamp), uip.UserCreationDate) AS UserAccountAge,
    EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - uip.UserCreationDate)) / (60 * 60 * 24 * 365.25) AS UserAgeInYears,
    uip.TotalPostsOwned,
    uip.TotalQuestionsOwned,
    uip.TotalAnswersOwned,
    uip.TotalCommentsMade,
    uip.GoldBadges,
    uip.SilverBadges,
    uip.BronzeBadges,
    uip.MostFrequentTag,
    uip.TopQuestionScoreByViews,
    COALESCE(uip.AvgQuestionScore, 0.0) AS AverageQuestionScore,
    COALESCE(uip.AvgAnswerScore, 0.0) AS AverageAnswerScore,
    NULLIF(uip.TotalEditsMade, 0) AS UserTotalEdits,
    uip.MostRecentEdit,
    uip.AvgReputationInLocation,
    UPPER(SUBSTRING(uip.DisplayName FROM 1 FOR 3)) || '...' AS DisplayNamePrefix,
    uip.AboutMeLength,
    uip.ProfileViews / NULLIF(EXTRACT(DAY FROM AGE(CAST('2024-10-01 12:34:56' AS timestamp), uip.UserCreationDate)), 0) AS AvgDailyProfileViews,
    (SELECT COUNT(DISTINCT pl.PostId) FROM PostLinks pl WHERE pl.PostId IN (SELECT p.Id FROM Posts p WHERE p.OwnerUserId = uip.UserId) AND pl.LinkTypeId = 1) AS TotalLinkedPostsByOwner,
    NULL AS RecentPostsCount,
    NULL AS RecentCommentsCount,
    NULL AS RecentEditsCount,
    NULL AS AvgQScoreLast2Y,
    NULL AS TotalBountyPosted
FROM UserInfluenceProfile uip
WHERE uip.Reputation >= 1000
    AND uip.TotalPostsOwned > 0
    AND uip.UserCreationDate < CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
    AND uip.MostFrequentTag IS NOT NULL
    AND uip.AboutMeLength > 100
    AND uip.ProfileViews > 1000
    AND EXISTS (
        SELECT 1
        FROM Badges b_exist
        WHERE b_exist.UserId = uip.UserId AND b_exist.Class = 1
        LIMIT 1
    )
    AND uip.AvgReputationInLocation > 0

UNION ALL

SELECT
    ras.UserId,
    ras.DisplayName,
    'Active-Contributor' AS UserCategory,
    ras.Reputation,
    NULL AS GlobalInfluenceRank,
    NULL AS ReputationQuintile,
    NULL AS InfluenceTier,
    AGE(CAST('2024-10-01 12:34:56' AS timestamp), ras.UserCreationDate) AS UserAccountAge,
    EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - ras.UserCreationDate)) / (60 * 60 * 24 * 365.25) AS UserAgeInYears,
    ucs.TotalPostsOwned,
    ucs.TotalQuestionsOwned,
    ucs.TotalAnswersOwned,
    ucs.TotalCommentsMade,
    ucs.GoldBadges,
    ucs.SilverBadges,
    ucs.BronzeBadges,
    (SELECT qtm_inner.TagName
     FROM QuestionTagMetrics_Flat qtm_inner
     WHERE qtm_inner.UserId = ras.UserId
     ORDER BY qtm_inner.QuestionsWithTag DESC, qtm_inner.AvgScoreForTag DESC
     LIMIT 1) AS MostFrequentTag,
    (SELECT pps_sq.PostScore
     FROM PostPerformanceSummary pps_sq
     WHERE pps_sq.OwnerUserId = ras.UserId AND pps_sq.PostTypeId = 1
     ORDER BY pps_sq.ViewCount DESC
     LIMIT 1) AS TopQuestionScoreByViews,
    (SELECT AVG(pps_sq.PostScore) FROM PostPerformanceSummary pps_sq WHERE pps_sq.OwnerUserId = ras.UserId AND pps_sq.PostTypeId = 1) AS AverageQuestionScore,
    (SELECT AVG(pps_sq.PostScore) FROM PostPerformanceSummary pps_sq WHERE pps_sq.OwnerUserId = ras.UserId AND pps_sq.PostTypeId = 2) AS AverageAnswerScore,
    (SELECT SUM(pps_sq.EditCount) FROM PostPerformanceSummary pps_sq WHERE pps_sq.OwnerUserId = ras.UserId) AS UserTotalEdits,
    (SELECT MAX(pps_sq.LastHistoryDate) FROM PostPerformanceSummary pps_sq WHERE pps_sq.OwnerUserId = ras.UserId) AS MostRecentEdit,
    NULL AS AvgReputationInLocation,
    UPPER(SUBSTRING(ras.DisplayName FROM 1 FOR 3)) || '...' AS DisplayNamePrefix,
    ucs.AboutMeLength,
    ucs.ProfileViews / NULLIF(EXTRACT(DAY FROM AGE(CAST('2024-10-01 12:34:56' AS timestamp), ras.UserCreationDate)), 0) AS AvgDailyProfileViews,
    (SELECT COUNT(DISTINCT pl.PostId) FROM PostLinks pl WHERE pl.PostId IN (SELECT p.Id FROM Posts p WHERE p.OwnerUserId = ras.UserId) AND pl.LinkTypeId = 1) AS TotalLinkedPostsByOwner,
    ras.RecentPosts AS RecentPostsCount,
    ras.RecentComments AS RecentCommentsCount,
    ras.RecentEdits AS RecentEditsCount,
    COALESCE(ras.AvgQuestionScoreLast2Years, 0.0) AS AvgQScoreLast2Y,
    COALESCE(ras.TotalBountyPosted, 0) AS TotalBounty
FROM RecentActivitySummary ras
LEFT JOIN UserCoreStats ucs ON ras.UserId = ucs.UserId;