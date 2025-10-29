-- {"query": "1092.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3690}
WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.AboutMe,
        u.WebsiteUrl,
        u.Location,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScoreReceived,
        SUM(CASE WHEN p.PostTypeId = 1 THEN COALESCE(p.ViewCount,0) ELSE 0 END) AS TotalQuestionViews,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        SUM(COALESCE(c.Score, 0)) AS TotalCommentScoreReceived,
        MAX(p.LastActivityDate) AS LastPostActivityDate,
        COUNT(DISTINCT CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN p.Id END) AS TotalAcceptedAnswers,
        COUNT(DISTINCT CASE WHEN p.ClosedDate IS NOT NULL AND p.PostTypeId = 1 THEN p.Id END) AS TotalClosedQuestions
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.AboutMe, u.WebsiteUrl, u.Location
),
BadgeCounts AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
        MAX(CASE WHEN b.Class = 1 THEN b.Date END) AS LastGoldBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
PostEditIntervals AS (
    SELECT
        ph.PostId,
        EXTRACT(EPOCH FROM (ph.CreationDate - prev_creation)) AS IntervalSeconds
    FROM (
        SELECT
            ph.*,
            LAG(ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS prev_creation
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId IN (4,5,6,7,8,9)
    ) ph
    WHERE prev_creation IS NOT NULL
),
PostEditMetrics AS (
    SELECT
        ph.PostId,
        COUNT(*) AS TotalEdits,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS ContentEdits,
        MIN(ph.CreationDate) AS FirstEditDate,
        MAX(ph.CreationDate) AS LastEditDate,
        AVG(pei.IntervalSeconds) AS AvgTimeBetweenEditsSeconds
    FROM PostHistory ph
    LEFT JOIN PostEditIntervals pei
      ON ph.PostId = pei.PostId
    WHERE ph.PostHistoryTypeId IN (4,5,6,7,8,9)
    GROUP BY ph.PostId
),
UserPostEditSummary AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT pem.PostId) AS PostsWithEdits,
        SUM(pem.TotalEdits) AS TotalUserPostEdits,
        AVG(pem.AvgTimeBetweenEditsSeconds) AS AvgTimeBetweenUserPostEdits,
        MAX(pem.LastEditDate) AS LastUserPostEditDate
    FROM Posts p
    JOIN PostEditMetrics pem ON p.Id = pem.PostId
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
RecentHighImpactPosts AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId AS PostOwnerUserId,
        p.Score AS PostScore,
        p.CreationDate AS PostCreationDate,
        p.AnswerCount,
        p.ViewCount,
        p.FavoriteCount,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS rn_post_score
    FROM Posts p
    WHERE p.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '6 months')
      AND p.PostTypeId = 1
      AND p.Score >= 5
      AND COALESCE(p.AnswerCount, 0) >= 2
),
AggregatedRecentHighImpactPosts AS (
    SELECT
        rhp.PostOwnerUserId AS UserId,
        COUNT(rhp.PostId) AS RecentHighImpactQuestionCount,
        SUM(rhp.PostScore) AS RecentHighImpactQuestionScoreSum,
        MAX(rhp.PostCreationDate) AS LatestHighImpactQuestionDate
    FROM RecentHighImpactPosts rhp
    WHERE rhp.rn_post_score <= 3
    GROUP BY rhp.PostOwnerUserId
),
UserTagCountsUnnested AS (
    SELECT
        p.OwnerUserId AS UserId,
        tag AS TagName
    FROM Posts p,
    LATERAL (
      SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag
    ) t
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND p.OwnerUserId IS NOT NULL
),
UserTagCountsRanked AS (
    SELECT
        utc.UserId,
        utc.TagName,
        COUNT(*) AS TagCount,
        ROW_NUMBER() OVER (PARTITION BY utc.UserId ORDER BY COUNT(*) DESC, utc.TagName ASC) AS rn
    FROM UserTagCountsUnnested utc
    GROUP BY utc.UserId, utc.TagName
),
UserTagInterest AS (
    SELECT
        utcr.UserId,
        utcr.TagName AS MostFrequentTag,
        utcr.TagCount AS MostFrequentTagCount
    FROM UserTagCountsRanked utcr
    WHERE utcr.rn = 1
),
CommentSentiment AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS TotalComments,
        SUM(CASE
                WHEN c.Text ILIKE '%great%' OR c.Text ILIKE '%thanks%' OR c.Text ILIKE '%helpful%' OR c.Text ILIKE '%solved%' THEN 1
                WHEN c.Text ILIKE '%problem%' OR c.Text ILIKE '%bug%' OR c.Text ILIKE '%error%' OR c.Text ILIKE '%broken%' THEN -1
                ELSE 0
            END) AS SentimentScore,
        AVG(CASE
                WHEN c.Text ILIKE '%great%' OR c.Text ILIKE '%thanks%' OR c.Text ILIKE '%helpful%' OR c.Text ILIKE '%solved%' THEN 1.0
                WHEN c.Text ILIKE '%problem%' OR c.Text ILIKE '%bug%' OR c.Text ILIKE '%error%' OR c.Text ILIKE '%broken%' THEN -1.0
                ELSE 0.0
            END) AS AvgCommentSentiment
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
PostAggregatedActivity AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId AS UserId,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS WasClosed,
        MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS WasReopened,
        COUNT(DISTINCT pl.RelatedPostId) AS LinkedPostsCount,
        COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.RelatedPostId END) AS DuplicateLinksCount,
        MAX(COALESCE(p.LastEditDate, p.CreationDate)) AS LatestPostActivity
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.Id, p.OwnerUserId
),
UserPostEngagement AS (
    SELECT
        paa.UserId,
        SUM(paa.WasClosed) AS TotalPostsClosed,
        SUM(paa.WasReopened) AS TotalPostsReopened,
        SUM(paa.LinkedPostsCount) AS TotalLinkedPosts,
        SUM(paa.DuplicateLinksCount) AS TotalDuplicateLinks,
        AVG(EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - paa.LatestPostActivity))/3600.0/24.0) AS AvgDaysSinceLastPostActivity
    FROM PostAggregatedActivity paa
    GROUP BY paa.UserId
),
UserTypeCategorization AS (
    SELECT
        uas.UserId,
        'Questioner' AS UserTypeCategory
    FROM UserActivitySummary uas
    WHERE uas.TotalQuestions > uas.TotalAnswers
       OR (uas.TotalQuestions > 0 AND uas.TotalAnswers = 0)
    UNION ALL
    SELECT
        uas.UserId,
        'Answerer' AS UserTypeCategory
    FROM UserActivitySummary uas
    WHERE uas.TotalAnswers > uas.TotalQuestions
       OR (uas.TotalAnswers > 0 AND uas.TotalQuestions = 0)
    UNION ALL
    SELECT
        uas.UserId,
        'Balanced/Other' AS UserTypeCategory
    FROM UserActivitySummary uas
    WHERE (uas.TotalQuestions = uas.TotalAnswers AND uas.TotalQuestions > 0)
       OR (uas.TotalQuestions = 0 AND uas.TotalAnswers = 0)
)
SELECT
    uas.UserId,
    COALESCE(uas.DisplayName, 'Deleted User (' || uas.UserId || ')') AS UserDisplayName,
    uas.Reputation,
    uas.UserCreationDate,
    uas.LastAccessDate,
    uas.TotalPosts,
    uas.TotalQuestions,
    uas.TotalAnswers,
    COALESCE(bc.GoldBadges, 0) AS GoldBadges,
    COALESCE(bc.SilverBadges, 0) AS SilverBadges,
    COALESCE(bc.BronzeBadges, 0) AS BronzeBadges,
    bc.LastGoldBadgeDate,
    COALESCE(upes.TotalUserPostEdits, 0) AS UserTotalEdits,
    COALESCE(upes.PostsWithEdits, 0) AS UserPostsEdited,
    COALESCE(upes.AvgTimeBetweenUserPostEdits, 0) AS AvgSecondsBetweenUserEdits,
    COALESCE(arihp.RecentHighImpactQuestionCount, 0) AS RecentHighImpactQCount,
    COALESCE(arihp.RecentHighImpactQuestionScoreSum, 0) AS RecentHighImpactQScoreSum,
    COALESCE(uti.MostFrequentTag, 'N/A') AS TopQuestionTag,
    COALESCE(uti.MostFrequentTagCount, 0) AS TopQuestionTagCount,
    COALESCE(cs.SentimentScore, 0) AS OverallCommentSentiment,
    COALESCE(cs.AvgCommentSentiment, 0.0) AS AvgCommentSentimentPerComment,
    COALESCE(upe.TotalPostsClosed, 0) AS UserPostsClosed,
    COALESCE(upe.TotalPostsReopened, 0) AS UserPostsReopened,
    COALESCE(upe.TotalLinkedPosts, 0) AS TotalLinkedPostsByUser,
    COALESCE(upe.TotalDuplicateLinks, 0) AS TotalDuplicateLinksByUser,
    COALESCE(upe.AvgDaysSinceLastPostActivity, 0.0) AS AvgDaysSinceUserPostActivity,
    uct.UserTypeCategory,
    CASE
        WHEN uas.Reputation >= 10000 AND COALESCE(bc.GoldBadges, 0) >= 5 THEN 'Legendary'
        WHEN uas.Reputation >= 5000 AND COALESCE(bc.GoldBadges, 0) >= 1 THEN 'Veteran'
        WHEN uas.Reputation >= 1000 THEN 'Pro'
        WHEN uas.Reputation >= 100 THEN 'Apprentice'
        ELSE 'Novice'
    END AS UserTier,
    (EXTRACT(YEAR FROM CAST('2024-10-01' AS date)) - EXTRACT(YEAR FROM uas.UserCreationDate)) AS YearsOnPlatform,
    (uas.TotalQuestions * 0.4 + uas.TotalAnswers * 0.6 + uas.TotalCommentsMade * 0.1) AS ActivityWeight,
    (uas.TotalPostScoreReceived * 0.7 + COALESCE(cs.SentimentScore, 0) * 0.3) AS ImpactScore,
    (SELECT c_latest.Text
     FROM Comments c_latest
     WHERE c_latest.UserId = uas.UserId
     ORDER BY c_latest.CreationDate DESC
     LIMIT 1) AS LatestCommentFromUser,
    (SELECT CASE WHEN COUNT(*)>0 THEN TRUE ELSE FALSE END
     FROM Badges b_sub
     WHERE b_sub.UserId = uas.UserId AND b_sub.Class = 1 AND b_sub.Name = 'Nice Answer') AS HasNiceAnswerGoldBadge,
    RANK() OVER (
        ORDER BY
            uas.Reputation DESC,
            (COALESCE(bc.GoldBadges, 0) * 100 + COALESCE(bc.SilverBadges, 0) * 10 + COALESCE(bc.BronzeBadges, 0)) DESC,
            uas.TotalPostScoreReceived DESC,
            COALESCE(arihp.RecentHighImpactQuestionScoreSum, 0) DESC,
            COALESCE(cs.SentimentScore, 0) DESC,
            uas.UserId ASC
    ) AS OverallUserRank
FROM UserActivitySummary uas
LEFT JOIN BadgeCounts bc ON uas.UserId = bc.UserId
LEFT JOIN UserPostEditSummary upes ON uas.UserId = upes.UserId
LEFT JOIN AggregatedRecentHighImpactPosts arihp ON uas.UserId = arihp.UserId
LEFT JOIN UserTagInterest uti ON uas.UserId = uti.UserId
LEFT JOIN CommentSentiment cs ON uas.UserId = cs.UserId
LEFT JOIN UserPostEngagement upe ON uas.UserId = upe.UserId
LEFT JOIN UserTypeCategorization uct ON uas.UserId = uct.UserId
WHERE
    uas.Reputation > 500
    AND (
        uas.LastAccessDate >= (CAST('2024-10-01' AS date) - INTERVAL '1 year')
        OR uas.TotalPosts > 100
        OR COALESCE(bc.GoldBadges, 0) > 0
    )
    AND uas.DisplayName IS NOT NULL
    AND uas.DisplayName NOT ILIKE '%deleted user%'
    AND ((uas.AboutMe IS NOT NULL AND LENGTH(uas.AboutMe) > 50) OR uas.WebsiteUrl IS NOT NULL)
    AND (uas.Location IS NULL OR uas.Location ILIKE '%america%' OR uas.Location ILIKE '%europe%')
ORDER BY OverallUserRank ASC, uas.UserId ASC
LIMIT 1000;