-- {"query": "58034.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1181} 
WITH ActiveUsers AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId IN (1, 2) AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 YEAR'
    LEFT JOIN Comments c ON u.Id = c.UserId AND c.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '6 MONTHS'
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2, 3, 8) AND v.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 YEAR'
    WHERE u.Reputation > 10000 AND u.LastAccessDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '90 DAYS'
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(p.Id) > 50 OR COUNT(c.Id) > 100
),
BadgeStats AS (
    SELECT 
        UserId,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        RANK() OVER (PARTITION BY Class ORDER BY COUNT(*) DESC) AS BadgeClassRank
    FROM Badges
    WHERE Date >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '2 YEARS'
    GROUP BY UserId, Class
)
SELECT 
    au.Id,
    au.DisplayName,
    au.Reputation,
    au.TotalPosts,
    au.TotalComments,
    au.TotalVotes,
    au.ReputationRank,
    bs.GoldBadges,
    bs.SilverBadges,
    bs.BronzeBadges,
    DENSE_RANK() OVER (ORDER BY (au.TotalPosts * 3 + au.TotalComments * 2 + au.TotalVotes) DESC) AS ActivityScore,
    CASE 
        WHEN bs.GoldBadges > 10 THEN 'Elite'
        WHEN bs.SilverBadges > 20 THEN 'Active Contributor'
        ELSE 'Regular User'
    END AS UserTier
FROM ActiveUsers au
JOIN BadgeStats bs ON au.Id = bs.UserId
WHERE bs.GoldBadges + bs.SilverBadges + bs.BronzeBadges > 25
ORDER BY 
    au.ReputationRank,
    ActivityScore,
    bs.GoldBadges DESC
LIMIT 100;