-- {"query": "18083.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1482} 

WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate,
        ph.PostHistoryTypeId,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
),
UserPostActivity AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(p.ViewCount) AS TotalViews,
        SUM(p.Score) AS TotalScore,
        AVG(p.AnswerCount) AS AvgAnswerCount,
        COUNT(DISTINCT c.Id) AS TotalComments
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId != -1
    GROUP BY p.OwnerUserId
),
PostEditFrequency AS (
    SELECT
        rpe.UserId,
        COUNT(DISTINCT rpe.PostId) AS DistinctPostsEdited,
        COUNT(*) AS TotalEdits,
        AVG(DATEDIFF(day, LAG(rpe.CreationDate, 1, rpe.CreationDate) OVER (PARTITION BY rpe.UserId ORDER BY rpe.CreationDate), rpe.CreationDate)) AS AvgDaysBetweenEdits
    FROM RankedPostEdits rpe
    GROUP BY rpe.UserId
),
UserBadgeSummary AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
FrequentEditorsWithHighRep AS (
    SELECT
        upe.OwnerUserId,
        MAX(upe.TotalPosts) AS MaxTotalPosts,
        MAX(upe.TotalScore) AS MaxTotalScore,
        MAX(pef.TotalEdits) AS MaxTotalEdits,
        MAX(ubs.GoldBadges) AS MaxGoldBadges
    FROM UserPostActivity upe
    LEFT JOIN PostEditFrequency pef ON upe.OwnerUserId = pef.UserId
    LEFT JOIN UserBadgeSummary ubs ON upe.OwnerUserId = ubs.UserId
    WHERE pef.TotalEdits IS NOT NULL AND pef.TotalEdits > 50 AND upe.TotalScore > 10000
    GROUP BY upe.OwnerUserId
),
RecentHighScoreQuestions AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.Title,
        p.Score,
        p.CreationDate,
        p.AnswerCount,
        ROW_NUMBER() OVER(PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as RecentQrn
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Score > 100 AND p.CreationDate > DATEADD(month, -6, GETDATE())
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.Views AS UserViews,
    upa.TotalPosts,
    upa.QuestionCount,
    upa.AnswerCount,
    upa.TotalComments,
    COALESCE(pef.TotalEdits, 0) AS TotalPostEdits,
    COALESCE(pef.AvgDaysBetweenEdits, 0) AS AvgDaysBetweenEdits,
    COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
    COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(rhsq.Title, 'No recent high-score questions') AS RecentHighScoreQuestionTitle,
    CASE WHEN u.LastAccessDate > DATEADD(day, -30, GETDATE()) THEN 'Active' ELSE 'Inactive' END AS UserActivityStatus,
    CASE WHEN ubs.GoldBadges > 5 THEN 'Elite' WHEN ubs.SilverBadges > 10 THEN 'Distinguished' ELSE 'Standard' END AS BadgeTier,
    ABS(DATEDIFF(year, u.CreationDate, u.LastAccessDate)) AS YearsSinceCreationToLastAccess,
    SUBSTRING(u.AboutMe, 1, 50) AS AboutMeSnippet,
    CASE WHEN u.WebsiteUrl IS NULL OR u.WebsiteUrl = '' THEN 'No Website' ELSE 'Has Website' END AS WebsiteStatus,
    (upa.TotalScore * 1.0 / NULLIF(upa.TotalPosts, 0)) AS AvgScorePerPost,
    CASE
        WHEN pht.Name IS NOT NULL AND pht.Name LIKE '%Edit%' THEN 'Post has been edited'
        WHEN c.Id IS NOT NULL THEN 'Post has comments'
        WHEN pl.PostId IS NOT NULL THEN 'Post has links'
        ELSE 'No specific activity'
    END AS PostActivityType
FROM Users u
LEFT JOIN UserPostActivity upa ON u.Id = upa.OwnerUserId
LEFT JOIN PostEditFrequency pef ON u.Id = pef.UserId
LEFT JOIN UserBadgeSummary ubs ON u.Id = ubs.UserId
LEFT JOIN (
    SELECT * FROM RecentHighScoreQuestions WHERE RecentQrn = 1
) AS rhsq ON u.Id = rhsq.OwnerUserId
LEFT JOIN PostHistory ph ON u.Id = ph.UserId
LEFT JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id AND pht.Name LIKE '%Edit%'
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN PostLinks pl ON u.Id = pl.PostId
WHERE u.Reputation > 5000 AND u.Id IN (SELECT OwnerUserId FROM FrequentEditorsWithHighRep)
ORDER BY u.Reputation DESC
OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY;
