-- {"query": "13093.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 653} 

WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        AVG(u.Reputation) OVER (PARTITION BY b.Class ORDER BY u.Reputation DESC) AS AvgRepByBadgeClass,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, b.Class
),
PostPerformance AS (
    SELECT
        p.OwnerUserId,
        p.Id AS PostId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostType,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousScore,
        DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS UserPostRank
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) AND p.ClosedDate IS NULL
),
TopContributors AS (
    SELECT
        u.UserId,
        u.DisplayName,
        SUM(p.Score) AS TotalScore,
        COUNT(p.PostId) AS TotalPosts,
        AVG(NULLIF(p.Score, 0)) AS AvgScore
    FROM UserActivity u
    JOIN PostPerformance p ON u.UserId = p.OwnerUserId
    WHERE p.CreationDate > CURRENT_DATE - INTERVAL '1 year'
    GROUP BY u.UserId, u.DisplayName
    HAVING COUNT(p.PostId) > 10
)
SELECT
    tc.DisplayName,
    tc.TotalScore,
    tc.TotalPosts,
    ROUND(tc.AvgScore, 2) AS AvgScore,
    ua.BadgeCount,
    ua.GoldBadges,
    STRING_AGG(DISTINCT CASE WHEN ua.ReputationRank <= 10 THEN ua.DisplayName END, ', ') AS TopReputationUsers
FROM TopContributors tc
JOIN UserActivity ua ON tc.UserId = ua.UserId
GROUP BY tc.DisplayName, tc.TotalScore, tc.TotalPosts, tc.AvgScore, ua.BadgeCount, ua.GoldBadges
ORDER BY tc.TotalScore DESC
LIMIT 20;
