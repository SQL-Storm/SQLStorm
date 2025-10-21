-- {"query": "1034.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 725} 
WITH UserReputation AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(b.Id) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostStats AS (
    SELECT 
        p.OwnerUserId,
        COUNT(p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        SUM(p.Score) AS TotalScore,
        SUM(p.ViewCount) AS TotalViews,
        MAX(p.CreationDate) AS LastPostDate
    FROM Posts p
    GROUP BY p.OwnerUserId
),
RecentUserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COALESCE(ps.TotalPosts, 0) AS TotalPosts,
        COALESCE(ps.TotalQuestions, 0) AS TotalQuestions,
        COALESCE(ps.TotalAnswers, 0) AS TotalAnswers,
        COALESCE(ps.TotalScore, 0) AS TotalScore,
        COALESCE(ps.TotalViews, 0) AS TotalViews,
        ra.LastPostDate
    FROM Users u
    LEFT JOIN PostStats ps ON u.Id = ps.OwnerUserId
    LEFT JOIN (
        SELECT 
            OwnerUserId,
            MAX(CreationDate) AS LastPostDate
        FROM Posts
        WHERE CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days'
        GROUP BY OwnerUserId
    ) ra ON u.Id = ra.OwnerUserId
),
RankedUsers AS (
    SELECT 
        u.UserId,
        u.DisplayName,
        u.Reputation,
        u.BadgeCount,
        u.GoldBadges,
        u.SilverBadges,
        u.BronzeBadges,
        a.TotalPosts,
        a.TotalQuestions,
        a.TotalAnswers,
        a.TotalScore,
        a.TotalViews,
        a.LastPostDate,
        RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM UserReputation u
    JOIN RecentUserActivity a ON u.UserId = a.UserId
)
SELECT 
    ru.DisplayName,
    ru.Reputation,
    ru.BadgeCount,
    ru.GoldBadges,
    ru.SilverBadges,
    ru.BronzeBadges,
    ru.TotalPosts,
    ru.TotalQuestions,
    ru.TotalAnswers,
    ru.TotalScore,
    ru.TotalViews,
    ru.LastPostDate,
    CASE 
        WHEN ru.TotalPosts > 50 THEN 'Veteran' 
        WHEN ru.TotalPosts BETWEEN 20 AND 50 THEN 'Active Contributor'
        WHEN ru.TotalPosts BETWEEN 1 AND 19 THEN 'New Contributor'
        ELSE 'No Activity' 
    END AS ActivityLevel
FROM RankedUsers ru
WHERE ru.ReputationRank <= 100 
ORDER BY ru.Reputation DESC, ru.LastPostDate DESC
LIMIT 10;