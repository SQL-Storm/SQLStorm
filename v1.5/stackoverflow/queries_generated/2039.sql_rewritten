-- {"query": "2039.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 430} 
WITH RecentBadges AS (
    SELECT 
        b.UserId, 
        b.Name AS BadgeName,
        row_number() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) as BadgeRank
    FROM 
        Badges b
),

TopBadgeHolders AS (
    SELECT 
        rb.UserId, 
        COUNT(*) OVER (PARTITION BY rb.UserId) AS BadgeCount
    FROM 
        RecentBadges rb
    WHERE 
        rb.BadgeRank = 1
),

UserPostMetrics AS (
    SELECT
        p.OwnerUserId,
        SUM(p.ViewCount) AS TotalViews,
        AVG(p.Score) AS AvgScore,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount
    FROM 
        Posts p
    WHERE 
        p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
    GROUP BY 
        p.OwnerUserId
)

SELECT
    u.DisplayName,
    u.Reputation,
    COALESCE(tb.BadgeCount, 0) AS TotalBadges,
    COALESCE(up.TotalViews, 0) AS TotalPostViews,
    COALESCE(up.AvgScore, 0) AS AveragePostScore,
    COALESCE(up.QuestionCount, 0) AS TotalQuestions,
    COALESCE(up.AnswerCount, 0) AS TotalAnswers,
    CASE 
        WHEN u.Views > 1000 THEN 'Popular'
        ELSE 'Regular'
    END as UserPopularity
FROM 
    Users u
LEFT JOIN
    TopBadgeHolders tb ON u.Id = tb.UserId
LEFT JOIN
    UserPostMetrics up ON u.Id = up.OwnerUserId
WHERE 
    u.CreationDate < cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '2 years'
  AND (u.Location ILIKE '%United States%' OR u.Location IS NULL)
ORDER BY 
    u.Reputation DESC, TotalBadges DESC;