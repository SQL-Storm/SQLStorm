
WITH UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
        SUM(p.Score) AS TotalScore,
        SUM(COALESCE(p.ViewCount, 0)) AS TotalViews,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName
),
RankedUsers AS (
    SELECT 
        UserId,
        DisplayName,
        TotalPosts,
        Questions,
        Answers,
        TotalScore,
        TotalViews,
        GoldBadges,
        @row_number := IF(@prev_total_score = TotalScore, @row_number, @row_number + 1) AS UserRank,
        @prev_total_score := TotalScore
    FROM UserPostStats, (SELECT @row_number := 0, @prev_total_score := NULL) AS vars
    ORDER BY TotalScore DESC, TotalPosts DESC
)
SELECT 
    u.UserId,
    u.DisplayName,
    u.TotalPosts,
    u.Questions,
    u.Answers,
    u.TotalScore,
    u.TotalViews,
    u.GoldBadges
FROM RankedUsers u
WHERE u.UserRank <= 10
ORDER BY u.TotalScore DESC, u.TotalPosts DESC;
