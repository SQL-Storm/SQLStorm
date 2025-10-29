-- {"query": "4184.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2016} 

WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edits: Title, Body, Tags
),
UserContributionSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS QuestionsAnswered,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersProvided,
        SUM(CASE WHEN p.PostTypeId = 1 AND p.OwnerUserId = u.Id THEN 1 ELSE 0 END) AS QuestionsAsked,
        MAX(u.Reputation) AS MaxReputation,
        AVG(u.Views) AS AvgUserViews,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        COALESCE(SUM(CASE WHEN pht.Name = 'Post Closed' THEN 1 ELSE 0 END), 0) AS PostsClosedCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    LEFT JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    GROUP BY u.Id, u.DisplayName
),
PostQualityMetrics AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
        COALESCE(p.Score, 0) + COALESCE(p.ViewCount, 0) AS EngagementScore,
        CASE
            WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN CAST(p.Score AS REAL) / p.AnswerCount
            ELSE NULL
        END AS ScorePerAnswer,
        REPLACE(p.Title, ' ', '_') AS FormattedTitle
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) AND p.OwnerUserId IS NOT NULL
),
RecentActivity AS (
    SELECT
        PostId,
        MAX(CreationDate) AS LastPostActivity
    FROM PostHistory
    WHERE PostHistoryTypeId IN (2, 5, 8) -- Body edits
    GROUP BY PostId
)
SELECT
    'PerformanceBenchmark' AS ReportSection,
    ucs.DisplayName AS UserDisplayName,
    pqs.FormattedTitle AS PostTitle,
    ucs.QuestionsAsked,
    ucs.AnswersProvided,
    ucs.TotalBadges,
    pqs.Score,
    pqs.ViewCount,
    pqs.AnswerCount,
    pqs.CommentCount,
    pqs.FavoriteCount,
    pqs.IsClosed,
    pqs.EngagementScore,
    pqs.ScorePerAnswer,
    ra.LastPostActivity,
    CASE
        WHEN ucs.MaxReputation > 100000 THEN 'Legendary'
        WHEN ucs.MaxReputation > 50000 THEN 'Expert'
        WHEN ucs.MaxReputation > 10000 THEN 'Experienced'
        ELSE 'Novice'
    END AS ReputationTier,
    CASE
        WHEN ucs.AvgUserViews < 1000 THEN 'Low'
        WHEN ucs.AvgUserViews < 10000 THEN 'Medium'
        ELSE 'High'
    END AS ViewershipTier,
    CASE
        WHEN COUNT(DISTINCT ph_recent.Id) > 5 THEN 'Very Active Editor'
        WHEN COUNT(DISTINCT ph_recent.Id) > 2 THEN 'Active Editor'
        ELSE 'Infrequent Editor'
    END AS EditingActivity,
    COALESCE(pqs.Score, 0) AS AdjustedScore,
    ABS(pqs.ViewCount - ucs.AvgUserViews) AS ViewCountDifference,
    CASE WHEN pqs.PostTypeId = 1 THEN 'Question' ELSE 'Answer' END AS PostTypeCategory,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = pqs.PostId AND c.Score > 5) AS HighScoringComments
FROM UserContributionSummary ucs
JOIN Posts p ON ucs.UserId = p.OwnerUserId AND p.PostTypeId IN (1, 2)
JOIN PostQualityMetrics pqs ON p.Id = pqs.PostId
LEFT JOIN RecentActivity ra ON p.Id = ra.PostId
LEFT JOIN PostHistory ph_recent ON p.Id = ph_recent.PostId AND ph_recent.PostHistoryTypeId IN (4, 5) -- Focus on body/title edits for activity
LEFT JOIN RankedPostEdits rpe ON p.Id = rpe.PostId AND ucs.UserId = rpe.UserId AND rpe.rn = 1
WHERE
    p.CreationDate >= DATE('now', '-1 year')
    AND ucs.QuestionsAnswered > 0
    AND pqs.Score > 0
    AND pqs.ViewCount > 100
    AND ucs.TotalBadges > 0
    AND ucs.PostsClosedCount < 5
GROUP BY
    ucs.DisplayName,
    pqs.FormattedTitle,
    ucs.QuestionsAsked,
    ucs.AnswersProvided,
    ucs.TotalBadges,
    pqs.Score,
    pqs.ViewCount,
    pqs.AnswerCount,
    pqs.CommentCount,
    pqs.FavoriteCount,
    pqs.IsClosed,
    pqs.EngagementScore,
    pqs.ScorePerAnswer,
    ra.LastPostActivity,
    ReputationTier,
    ViewershipTier,
    pqs.PostTypeId,
    pqs.OwnerUserId
HAVING COUNT(DISTINCT ph_recent.Id) > 1 OR COUNT(DISTINCT rpe.UserId) > 0
UNION ALL
SELECT
    'TopContributors' AS ReportSection,
    u.DisplayName AS UserDisplayName,
    NULL AS PostTitle,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsAsked,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersProvided,
    COUNT(DISTINCT b.Id) AS TotalBadges,
    NULL AS Score,
    SUM(p.ViewCount) AS ViewCount,
    NULL AS AnswerCount,
    NULL AS CommentCount,
    NULL AS FavoriteCount,
    NULL AS IsClosed,
    SUM(p.Score) AS EngagementScore,
    NULL AS ScorePerAnswer,
    MAX(p.LastActivityDate) AS LastPostActivity,
    CASE
        WHEN u.Reputation > 100000 THEN 'Legendary'
        WHEN u.Reputation > 50000 THEN 'Expert'
        WHEN u.Reputation > 10000 THEN 'Experienced'
        ELSE 'Novice'
    END AS ReputationTier,
    CASE
        WHEN u.Views < 1000 THEN 'Low'
        WHEN u.Views < 10000 THEN 'Medium'
        ELSE 'High'
    END AS ViewershipTier,
    CASE
        WHEN COUNT(DISTINCT ph.Id) > 10 THEN 'Very Active Editor'
        WHEN COUNT(DISTINCT ph.Id) > 5 THEN 'Active Editor'
        ELSE 'Infrequent Editor'
    END AS EditingActivity,
    u.Reputation AS AdjustedScore,
    NULL AS ViewCountDifference,
    'Overall' AS PostTypeCategory,
    NULL AS HighScoringComments
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN PostHistory ph ON u.Id = ph.UserId AND ph.PostHistoryTypeId IN (4, 5)
WHERE u.Id IN (SELECT OwnerUserId FROM Posts WHERE CreationDate >= DATE('now', '-3 months'))
GROUP BY
    u.Id, u.DisplayName, ReputationTier, ViewershipTier, u.Reputation, u.Views
HAVING COUNT(DISTINCT p.Id) > 50 OR COUNT(DISTINCT b.Id) > 10
ORDER BY
    CASE WHEN ReportSection = 'PerformanceBenchmark' THEN 1 ELSE 2 END,
    TotalBadges DESC,
    EngagementScore DESC NULLS LAST,
    UserDisplayName;
