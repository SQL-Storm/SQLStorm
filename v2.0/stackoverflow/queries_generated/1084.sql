-- {"query": "1084.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3068} 

WITH UserEngagement AS (
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScore,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.LastActivityDate) AS LastPostActivity,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS TotalEditsMadeByOwner,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS TotalClosesInitiatedByOwner,
        SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS TotalReopensInitiatedByOwner,
        COUNT(DISTINCT c.Id) AS TotalComments,
        SUM(COALESCE(c.Score, 0)) AS TotalCommentScore,
        AVG(c.Score) AS AvgCommentScore,
        MAX(c.CreationDate) AS LastCommentActivity
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.UserId = u.Id -- Only consider history events initiated by the post owner
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id
),
UserBadgeDistribution AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(b.Id) AS TotalBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
PostTagLinkAnalysis AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.CreationDate,
        p.Tags,
        COALESCE(
            COUNT(DISTINCT unnest(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><'))),
            0
        ) AS UniqueTagsCount,
        SUM(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS LinkedPostsCount,
        SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateLinksCount,
        MAX(CASE WHEN ph_close.PostHistoryTypeId = 10 AND ph_close.Comment = '101' THEN 1 ELSE 0 END) AS IsDuplicateClosedByNewReason,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVoteCountOnPost, -- UpMod
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVoteCountOnPost -- DownMod
    FROM Posts p
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId
    LEFT JOIN PostHistory ph_close ON p.Id = ph_close.PostId AND ph_close.PostHistoryTypeId = 10
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    WHERE p.PostTypeId IN (1, 2) -- Only questions and answers
      AND p.Tags IS NOT NULL
      AND LENGTH(p.Tags) > 2 -- Ensure tags are not empty after stripping <>
    GROUP BY p.Id, p.OwnerUserId, p.CreationDate, p.Tags
),
RankedInfluentialUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        ue.TotalQuestions,
        ue.TotalAnswers,
        ubd.GoldBadges,
        ubd.SilverBadges,
        ubd.BronzeBadges,
        (ue.TotalPostScore * 0.5) + (ue.TotalCommentScore * 0.2) + (ubd.GoldBadges * 100) + (ubd.SilverBadges * 50) - (ue.TotalClosesInitiatedByOwner * 20) AS CalculatedInfluenceScore,
        RANK() OVER (ORDER BY u.Reputation DESC, ue.TotalPosts DESC, ubd.GoldBadges DESC) AS OverallReputationRank,
        ROW_NUMBER() OVER (PARTITION BY u.Location ORDER BY u.Reputation DESC, ue.LastPostActivity DESC) AS RankInLocation,
        LAG(u.Reputation, 1, 0) OVER (PARTITION BY u.Location ORDER BY u.Reputation) AS PreviousUserReputationInLocation
    FROM Users u
    JOIN UserEngagement ue ON u.Id = ue.UserId
    LEFT JOIN UserBadgeDistribution ubd ON u.Id = ubd.UserId
    WHERE u.Location IS NOT NULL AND u.Location != ''
)
SELECT
    riu.DisplayName,
    riu.Reputation,
    riu.OverallReputationRank,
    riu.RankInLocation,
    riu.TotalQuestions,
    riu.TotalAnswers,
    riu.GoldBadges,
    riu.SilverBadges,
    riu.BronzeBadges,
    riu.CalculatedInfluenceScore,
    u.CreationDate AS UserCreationDate,
    COALESCE(ue.LastPostActivity, ue.LastCommentActivity, u.LastAccessDate) AS LastRecordedInteractionDate,
    EXTRACT(DAY FROM (CURRENT_TIMESTAMP - u.CreationDate)) AS UserAccountAgeDays,
    (
        SELECT c.Text
        FROM Comments c
        WHERE c.UserId = u.Id AND c.Score > 5
        ORDER BY c.CreationDate DESC
        LIMIT 1
    ) AS TopScoredRecentCommentText,
    LOWER(SUBSTRING(COALESCE(u.Location, 'UNKNOWN'), 1, LEAST(LENGTH(COALESCE(u.Location, 'UNKNOWN')), 5))) AS LocationPrefix,
    COUNT(DISTINCT pta.PostId) FILTER (WHERE pta.IsDuplicateClosedByNewReason = 1) AS QuestionsClosedAsDuplicateCount,
    SUM(COALESCE(pta.UpVoteCountOnPost, 0)) AS TotalUpvotesOnRelatedPosts,
    SUM(COALESCE(pta.DownVoteCountOnPost, 0)) AS TotalDownvotesOnRelatedPosts,
    MAX(ue.AvgPostScore) AS MaxAvgScoreAcrossAllUserPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.FavoriteCount > 100 AND p.ClosedDate IS NULL THEN p.Id END) AS ActiveHighlyFavoritedQuestions,
    (
        SELECT AVG(p_sub.Score)
        FROM Posts p_sub
        WHERE p_sub.OwnerUserId = u.Id
          AND p_sub.PostTypeId = 2
          AND p_sub.CreationDate > (CURRENT_TIMESTAMP - INTERVAL '1 year')
          AND p_sub.Score IS NOT NULL
    ) AS AvgAnswerScoreLastYear,
    COALESCE(u.AboutMe, 'No "About Me" provided') AS AboutMeSnippet
FROM RankedInfluentialUsers riu
JOIN Users u ON riu.UserId = u.Id
LEFT JOIN UserEngagement ue ON riu.UserId = ue.UserId
LEFT JOIN PostTagLinkAnalysis pta ON u.Id = pta.OwnerUserId
LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
WHERE
    riu.Reputation > 5000
    AND riu.GoldBadges >= 2
    AND riu.TotalQuestions >= 5
    AND ue.LastPostActivity > (CURRENT_TIMESTAMP - INTERVAL '6 months')
    AND u.AboutMe IS NOT NULL
    AND EXISTS (
        SELECT 1
        FROM PostTagLinkAnalysis pta_ex
        WHERE pta_ex.OwnerUserId = u.Id
          AND pta_ex.Tags ILIKE '%<sql>%'
          AND pta_ex.UniqueTagsCount >= 2
          AND pta_ex.CreationDate BETWEEN (CURRENT_TIMESTAMP - INTERVAL '2 years') AND CURRENT_TIMESTAMP
    )
GROUP BY
    riu.DisplayName, riu.Reputation, riu.OverallReputationRank, riu.RankInLocation, riu.TotalQuestions, riu.TotalAnswers,
    riu.GoldBadges, riu.SilverBadges, riu.BronzeBadges, riu.CalculatedInfluenceScore, u.CreationDate,
    ue.LastPostActivity, ue.LastCommentActivity, u.LastAccessDate, u.Id, u.AboutMe, u.Location
HAVING
    SUM(COALESCE(pta.LinkedPostsCount, 0)) > 0
    AND SUM(COALESCE(pta.DuplicateLinksCount, 0)) = 0
    AND COUNT(DISTINCT CASE WHEN p.Id IS NOT NULL AND p.ClosedDate IS NULL THEN p.Id END) >= 1 -- At least one open question
UNION ALL
SELECT
    u.DisplayName,
    u.Reputation,
    NULL AS OverallReputationRank,
    NULL AS RankInLocation,
    ue.TotalQuestions,
    ue.TotalAnswers,
    ubd.GoldBadges,
    ubd.SilverBadges,
    ubd.BronzeBadges,
    (ue.TotalEditsMadeByOwner * 0.7) + (ue.TotalClosesInitiatedByOwner * 0.8) + (ubd.GoldBadges * 75) AS CalculatedInfluenceScore,
    u.CreationDate AS UserCreationDate,
    COALESCE(ue.LastCommentActivity, u.LastAccessDate) AS LastRecordedInteractionDate,
    EXTRACT(DAY FROM (CURRENT_TIMESTAMP - u.CreationDate)) AS UserAccountAgeDays,
    NULL AS TopScoredRecentCommentText, -- Not retrieving comment text for this path to diversify cost
    UPPER(SUBSTRING(COALESCE(u.Location, 'NONE'), GREATEST(1, LENGTH(COALESCE(u.Location, 'NONE')) - 4))) AS LocationSuffix,
    COUNT(DISTINCT pta.PostId) FILTER (WHERE pta.IsDuplicateClosedByNewReason = 1) AS QuestionsClosedAsDuplicateCount,
    SUM(COALESCE(pta.UpVoteCountOnPost, 0)) AS TotalUpvotesOnRelatedPosts,
    SUM(COALESCE(pta.DownVoteCountOnPost, 0)) AS TotalDownvotesOnRelatedPosts,
    MAX(ue.AvgPostScore) AS MaxAvgScoreAcrossAllUserPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.CommentCount > 50 THEN p.Id END) AS HighlyCommentedQuestions,
    NULL AS AvgAnswerScoreLastYear, -- Not calculating for this path
    COALESCE(u.AboutMe, 'No "About Me" provided') AS AboutMeSnippet
FROM Users u
JOIN UserEngagement ue ON u.Id = ue.UserId
LEFT JOIN UserBadgeDistribution ubd ON u.Id = ubd.UserId
LEFT JOIN PostTagLinkAnalysis pta ON u.Id = pta.OwnerUserId
LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
WHERE
    u.Reputation BETWEEN 2000 AND 10000
    AND ue.TotalEditsMadeByOwner > 100
    AND ue.TotalClosesInitiatedByOwner > 10
    AND ubd.SilverBadges >= 5
    AND u.WebsiteUrl IS NOT NULL
    AND NOT EXISTS (
        SELECT 1
        FROM Posts p_no_recent_activity
        WHERE p_no_recent_activity.OwnerUserId = u.Id
          AND p_no_recent_activity.LastActivityDate > (CURRENT_TIMESTAMP - INTERVAL '3 months')
          AND p_no_recent_activity.PostTypeId IN (1,2)
    ) -- Users without recent post activity in questions/answers
    AND u.Location IS NOT NULL AND LENGTH(u.Location) > 5 -- ensure location has enough characters for suffix
    AND u.Views > (SELECT AVG(Views) FROM Users) -- Views above average
GROUP BY
    u.DisplayName, u.Reputation, ue.TotalQuestions, ue.TotalAnswers, ubd.GoldBadges, ubd.SilverBadges,
    ubd.BronzeBadges, ue.TotalEditsMadeByOwner, ue.TotalClosesInitiatedByOwner, u.CreationDate,
    ue.LastCommentActivity, u.LastAccessDate, u.Id, u.Location, u.AboutMe, u.Views
HAVING
    COUNT(DISTINCT pta.PostId) FILTER (WHERE pta.UniqueTagsCount > 5) >= 1 -- At least one post with more than 5 unique tags
    AND SUM(COALESCE(pta.DownVoteCountOnPost, 0)) < 100 -- Users who aren't primarily controversial
ORDER BY
    Reputation DESC, CalculatedInfluenceScore DESC, UserCreationDate ASC;
