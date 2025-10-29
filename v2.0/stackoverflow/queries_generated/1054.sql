-- {"query": "1054.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3491} 

WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Views AS TotalProfileViews,
        u.UpVotes AS TotalUpVotesGiven,
        u.DownVotes AS TotalDownVotesGiven,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COALESCE(AVG(p.Score), 0.0) AS AvgPostScore,
        COUNT(DISTINCT c.Id) AS TotalComments,
        (EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - u.CreationDate)) / 86400.0) AS AccountAgeDays, -- PostgreSQL specific date diff in days
        CASE
            WHEN (EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - u.CreationDate)) / 86400.0) + 1 <= 0 THEN 0.0 -- Avoid division by zero or negative age
            ELSE CAST(u.Reputation AS REAL) / ((EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - u.CreationDate)) / 86400.0) + 1)
        END AS RepPerDay
    FROM Users AS u
    LEFT JOIN Posts AS p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments AS c ON u.Id = c.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes
),
PostExpandedTags AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        TRIM(UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><'))) AS TagName -- PostgreSQL specific string parsing
    FROM Posts AS p
    WHERE p.Tags IS NOT NULL AND p.PostTypeId = 1 -- Only questions for tag analysis
),
TagOverallStats AS (
    SELECT
        pet.TagName,
        COUNT(DISTINCT pet.PostId) AS TaggedPostsCount,
        SUM(pet.Score) AS TaggedPostsTotalScore,
        AVG(pet.Score) AS TaggedPostsAvgScore,
        AVG(pet.ViewCount) AS TaggedPostsAvgViewCount,
        COALESCE(MAX(t.Count), 0) AS GlobalTagUseCount, -- from the Tags table
        RANK() OVER (ORDER BY SUM(pet.Score) DESC, COUNT(DISTINCT pet.PostId) DESC) AS TagScoreRank
    FROM PostExpandedTags AS pet
    LEFT JOIN Tags AS t ON pet.TagName = t.TagName
    GROUP BY pet.TagName
),
UserTagContributions AS (
    SELECT
        pet.OwnerUserId AS UserId,
        pet.TagName,
        COUNT(pet.PostId) AS UserTagPosts,
        SUM(pet.Score) AS UserTagScore,
        AVG(pet.Score) AS UserAvgTagScore,
        RANK() OVER (PARTITION BY pet.OwnerUserId ORDER BY SUM(pet.Score) DESC, COUNT(pet.PostId) DESC) AS UserTagRank
    FROM PostExpandedTags AS pet
    GROUP BY pet.OwnerUserId, pet.TagName
),
UserPostEngagementSummary AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(p.Id) AS UserTotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS UserQuestionsCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS UserAnswersCount,
        SUM(CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswers,
        SUM(CASE WHEN p.PostTypeId = 2 AND q.AcceptedAnswerId = p.Id THEN 1 ELSE 0 END) AS AcceptedAnswersGiven,
        COALESCE(AVG(p.Score), 0.0) AS UserAvgPostScore,
        COALESCE(SUM(p.FavoriteCount), 0) AS TotalPostsFavorited,
        COUNT(DISTINCT ph_edit.Id) AS PostEditHistoryCount,
        COUNT(DISTINCT ph_neg.Id) AS PostNegativeHistoryCount
    FROM Posts AS p
    LEFT JOIN Posts AS q ON p.ParentId = q.Id AND p.PostTypeId = 2 -- Link answers to their questions
    LEFT JOIN PostHistory AS ph_edit ON p.Id = ph_edit.PostId AND p.OwnerUserId = ph_edit.UserId AND ph_edit.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) -- Edits/Rollbacks of title/body/tags
    LEFT JOIN PostHistory AS ph_neg ON p.Id = ph_neg.PostId AND p.OwnerUserId = ph_neg.UserId AND ph_neg.PostHistoryTypeId IN (10, 12, 14, 35) -- Closed, Deleted, Locked, Migrated Away
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserBadgeStats AS (
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MIN(b.Date) AS FirstBadgeDate,
        MAX(b.Date) AS LastBadgeDate,
        COUNT(DISTINCT b.Name) AS UniqueBadgeNames
    FROM Badges AS b
    GROUP BY b.UserId
),
UserTemporalBadgeAnalysis AS (
    SELECT
        b.UserId,
        b.Date AS CurrentBadgeDate,
        LEAD(b.Date) OVER (PARTITION BY b.UserId ORDER BY b.Date) AS NextBadgeDate
    FROM Badges AS b
),
UserAvgBadgeInterval AS (
    SELECT
        UserId,
        AVG(EXTRACT(EPOCH FROM (NextBadgeDate - CurrentBadgeDate)) / 86400.0) AS AvgDaysBetweenBadges -- Difference in days
    FROM UserTemporalBadgeAnalysis
    WHERE NextBadgeDate IS NOT NULL
    GROUP BY UserId
),
HighImpactContributorCandidates AS (
    SELECT
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.RepPerDay,
        uas.TotalPosts,
        uas.TotalQuestions,
        uas.TotalAnswers,
        upe.AcceptedAnswersGiven,
        upe.QuestionsWithAcceptedAnswers,
        ubs.TotalBadges,
        ubs.GoldBadges,
        uabi.AvgDaysBetweenBadges,
        COALESCE(uts.TopTag, 'No Top Tag') AS TopTagContribution,
        COALESCE(CAST(uts.TopTagScore AS TEXT), 'N/A') AS TopTagScore,
        upe.PostEditHistoryCount,
        upe.PostNegativeHistoryCount,
        (upe.AcceptedAnswersGiven * 1.0 / NULLIF(upe.UserAnswersCount, 0)) AS AcceptedAnswerRatio,
        (uas.TotalPostScore * 1.0 / NULLIF(uas.TotalPosts, 0)) AS AvgScorePerPost,
        CASE
            WHEN upe.PostEditHistoryCount > 5 AND upe.PostNegativeHistoryCount < 3 THEN 'Active Maintainer'
            WHEN upe.PostEditHistoryCount <= 5 AND upe.PostNegativeHistoryCount >= 3 THEN 'Problematic Contributor'
            WHEN upe.PostEditHistoryCount > 0 OR upe.PostNegativeHistoryCount > 0 THEN 'Engaged'
            ELSE 'Passive'
        END AS UserContributionProfile,
        COALESCE(SUBSTRING(u.AboutMe FROM 1 FOR 50) || '...', 'No About Me') AS AboutMeSnippet,
        (SELECT COUNT(DISTINCT psub.Id)
         FROM Posts AS psub
         WHERE psub.OwnerUserId = uas.UserId
           AND psub.PostTypeId = 1
           AND psub.ViewCount > 10000
           AND psub.Score < 10
        ) AS HighViewLowScoreQuestions,
        EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = uas.UserId AND b.Name ILIKE '%suffrage%' AND b.Date > uas.LastAccessDate - INTERVAL '1 year') AS HasRecentSuffrageBadge,
        CASE
            WHEN uas.DisplayName IS NULL OR LENGTH(TRIM(uas.DisplayName)) = 0 THEN 'Anonymous User'
            ELSE uas.DisplayName
        END AS ValidatedDisplayName
    FROM UserActivitySummary AS uas
    INNER JOIN Users AS u ON uas.UserId = u.Id
    LEFT JOIN UserPostEngagementSummary AS upe ON uas.UserId = upe.UserId
    LEFT JOIN UserBadgeStats AS ubs ON uas.UserId = ubs.UserId
    LEFT JOIN UserAvgBadgeInterval AS uabi ON uas.UserId = uabi.UserId
    LEFT JOIN (
        SELECT
            UserId,
            TagName AS TopTag,
            UserTagScore AS TopTagScore
        FROM UserTagContributions
        WHERE UserTagRank = 1
    ) AS uts ON uas.UserId = uts.UserId
    WHERE uas.Reputation >= 1000
      AND uas.TotalPosts >= 10
      AND uas.AccountAgeDays >= 365
      AND (upe.AcceptedAnswersGiven > 0 OR upe.UserQuestionsCount > 0)
      AND uas.DisplayName IS NOT NULL
      AND (
            (ubs.GoldBadges > 0 AND uas.RepPerDay > 5)
            OR
            (upe.AcceptedAnswersGiven >= 5 AND upe.UserAnswersCount > 10)
            OR
            EXISTS (SELECT 1 FROM UserTagContributions utc_sub JOIN TagOverallStats tos_sub ON utc_sub.TagName = tos_sub.TagName WHERE utc_sub.UserId = uas.UserId AND utc_sub.UserTagScore > 100 AND tos_sub.TagScoreRank <= 10)
      )
),
CommunityEngagerCandidates AS (
    SELECT
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.RepPerDay,
        uas.TotalPosts,
        uas.TotalQuestions,
        uas.TotalAnswers,
        upe.AcceptedAnswersGiven,
        upe.QuestionsWithAcceptedAnswers,
        ubs.TotalBadges,
        ubs.GoldBadges,
        uabi.AvgDaysBetweenBadges,
        COALESCE(uts.TopTag, 'No Top Tag') AS TopTagContribution,
        COALESCE(CAST(uts.TopTagScore AS TEXT), 'N/A') AS TopTagScore,
        upe.PostEditHistoryCount,
        upe.PostNegativeHistoryCount,
        (upe.AcceptedAnswersGiven * 1.0 / NULLIF(upe.UserAnswersCount, 0)) AS AcceptedAnswerRatio,
        (uas.TotalPostScore * 1.0 / NULLIF(uas.TotalPosts, 0)) AS AvgScorePerPost,
        CASE
            WHEN uas.TotalComments > 1000 THEN 'Pro Commenter'
            WHEN uas.TotalUpVotesGiven > 500 THEN 'Active Voter'
            ELSE 'General Engager'
        END AS UserContributionProfile,
        COALESCE(SUBSTRING(u.AboutMe FROM 1 FOR 50) || '...', 'No About Me') AS AboutMeSnippet,
        (SELECT COUNT(DISTINCT csub.Id)
         FROM Comments AS csub
         WHERE csub.UserId = uas.UserId
           AND csub.Score >= 5
           AND csub.CreationDate > CURRENT_TIMESTAMP - INTERVAL '6 months'
        ) AS HighViewLowScoreQuestions,
        EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = uas.UserId AND b.TagBased = TRUE AND b.Date > uas.LastAccessDate - INTERVAL '6 months') AS HasRecentSuffrageBadge,
        CASE
            WHEN uas.DisplayName IS NULL OR LENGTH(TRIM(uas.DisplayName)) = 0 THEN 'Anonymous User'
            ELSE uas.DisplayName
        END AS ValidatedDisplayName
    FROM UserActivitySummary AS uas
    INNER JOIN Users AS u ON uas.UserId = u.Id
    LEFT JOIN UserPostEngagementSummary AS upe ON uas.UserId = upe.UserId
    LEFT JOIN UserBadgeStats AS ubs ON uas.UserId = ubs.UserId
    LEFT JOIN UserAvgBadgeInterval AS uabi ON uas.UserId = uabi.UserId
    LEFT JOIN (
        SELECT
            UserId,
            TagName AS TopTag,
            UserTagScore AS TopTagScore
        FROM UserTagContributions
        WHERE UserTagRank = 1
    ) AS uts ON uas.UserId = uts.UserId
    WHERE uas.Reputation >= 100
      AND uas.TotalComments >= 50
      AND uas.AccountAgeDays >= 90
      AND (uas.TotalUpVotesGiven > 100 OR ubs.TotalBadges > 5)
      AND uas.DisplayName IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM HighImpactContributorCandidates hcc WHERE hcc.UserId = uas.UserId) -- Exclude users from the first branch
)
SELECT
    'HighImpactContributor' AS UserCategory,
    hcc.UserId,
    hcc.DisplayName,
    hcc.Reputation,
    hcc.RepPerDay,
    hcc.TotalPosts,
    hcc.TotalQuestions,
    hcc.TotalAnswers,
    hcc.AcceptedAnswersGiven,
    hcc.QuestionsWithAcceptedAnswers,
    hcc.TotalBadges,
    hcc.GoldBadges,
    hcc.AvgDaysBetweenBadges,
    hcc.TopTagContribution,
    hcc.TopTagScore,
    hcc.PostEditHistoryCount,
    hcc.PostNegativeHistoryCount,
    ROW_NUMBER() OVER (ORDER BY hcc.Reputation DESC, hcc.AcceptedAnswersGiven DESC) AS OverallRank,
    DENSE_RANK() OVER (PARTITION BY hcc.GoldBadges > 0 ORDER BY hcc.RepPerDay DESC) AS RankByGoldBadgeStatus,
    NTILE(10) OVER (ORDER BY hcc.TotalPostScore DESC) AS UserScoreDecile,
    hcc.AcceptedAnswerRatio,
    hcc.AvgScorePerPost,
    hcc