-- {"query": "43014.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 678} 
WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(p.Score) AS TotalScore,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS TotalQuestionViews,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.ViewCount ELSE 0 END) AS TotalAnswerViews,
        COUNT(DISTINCT ph.Id) AS EditHistoryCount
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId AND ph.PostHistoryTypeId IN (4, 5, 6)
    WHERE u.CreationDate >= DATE_TRUNC('year', cast('2024-10-01' as date)) - INTERVAL '1 year'
    GROUP BY u.Id, u.DisplayName
),
TopContributors AS (
    SELECT 
        UserId,
        DisplayName,
        TotalBadges,
        GoldBadges,
        SilverBadges,
        BronzeBadges,
        TotalPosts,
        TotalQuestions,
        TotalAnswers,
        TotalScore,
        TotalQuestionViews,
        TotalAnswerViews,
        EditHistoryCount,
        RANK() OVER (ORDER BY TotalScore DESC) AS ScoreRank,
        RANK() OVER (ORDER BY TotalBadges DESC) AS BadgeRank
    FROM UserActivity
)
SELECT 
    tc.UserId,
    tc.DisplayName,
    tc.TotalBadges,
    tc.GoldBadges,
    tc.SilverBadges,
    tc.BronzeBadges,
    tc.TotalPosts,
    tc.TotalQuestions,
    tc.TotalAnswers,
    tc.TotalScore,
    tc.TotalQuestionViews,
    tc.TotalAnswerViews,
    tc.EditHistoryCount,
    (SELECT AVG(TotalScore) FROM UserActivity) AS AvgTotalScore,
    (SELECT AVG(TotalBadges) FROM UserActivity) AS AvgTotalBadges
FROM TopContributors tc
WHERE tc.ScoreRank <= 10 OR tc.BadgeRank <= 10
ORDER BY GREATEST(tc.ScoreRank, tc.BadgeRank);