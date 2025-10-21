WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.LastActivityDate) AS LastActivityDate
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    WHERE 
        p.CreationDate >= DATE_TRUNC('month', CAST('2024-10-01' AS DATE)) - INTERVAL '1 year'
    GROUP BY 
        u.Id, u.DisplayName
),
TopContributors AS (
    SELECT 
        UserId,
        DisplayName,
        TotalPosts,
        TotalQuestions,
        TotalAnswers,
        AvgPostScore,
        LastActivityDate,
        ROW_NUMBER() OVER (ORDER BY TotalPosts DESC, AvgPostScore DESC) AS Rank
    FROM 
        UserActivity
    WHERE 
        TotalPosts > 10
),
RecentBadges AS (
    SELECT 
        b.UserId,
        b.Name,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) AS BadgeRank
    FROM 
        Badges b
    WHERE 
        b.Date >= DATE_TRUNC('month', CAST('2024-10-01' AS DATE)) - INTERVAL '3 months'
),
UserMetrics AS (
    SELECT
        tc.UserId,
        tc.DisplayName,
        tc.TotalPosts,
        tc.TotalQuestions,
        tc.TotalAnswers,
        tc.AvgPostScore,
        tc.LastActivityDate,
        STRING_AGG(rb.Name, ', ') FILTER (WHERE rb.BadgeRank <= 3) AS RecentBadges
    FROM 
        TopContributors tc
    LEFT JOIN 
        RecentBadges rb ON tc.UserId = rb.UserId
    WHERE
        tc.Rank <= 100
    GROUP BY 
        tc.UserId, tc.DisplayName, tc.TotalPosts, tc.TotalQuestions, tc.TotalAnswers, tc.AvgPostScore, tc.LastActivityDate
)
SELECT 
    um.UserId,
    um.DisplayName,
    COALESCE(um.TotalPosts, 0) AS TotalPosts,
    COALESCE(um.TotalQuestions, 0) AS TotalQuestions,
    COALESCE(um.TotalAnswers, 0) AS TotalAnswers,
    COALESCE(ROUND(um.AvgPostScore, 2), 0) AS AvgPostScore,
    um.LastActivityDate,
    COALESCE(um.RecentBadges, 'No recent badges') AS RecentBadges,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = um.UserId AND v.CreationDate >= DATE_TRUNC('month', CAST('2024-10-01' AS DATE)) - INTERVAL '6 months') AS VotesInLast6Months
FROM 
    UserMetrics um
ORDER BY 
    um.TotalPosts DESC, um.AvgPostScore DESC;