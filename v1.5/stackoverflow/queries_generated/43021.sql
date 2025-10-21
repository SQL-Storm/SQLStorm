-- {"query": "43021.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 447} 

WITH RecentActiveUsers AS (
    SELECT DISTINCT OwnerUserId
    FROM Posts
    WHERE LastActivityDate >= NOW() - INTERVAL '3 months'
),
TopContributors AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(p.Score) AS TotalScore,
        RANK() OVER (ORDER BY SUM(p.Score) DESC) AS Rank
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Id IN (SELECT OwnerUserId FROM RecentActiveUsers)
        AND p.CreationDate >= NOW() - INTERVAL '1 year'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
UserBadges AS (
    SELECT 
        UserId,
        COUNT(*) FILTER (WHERE Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE Class = 3) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
)
SELECT 
    tc.Id,
    tc.DisplayName,
    tc.Reputation,
    tc.QuestionCount,
    tc.AnswerCount,
    tc.TotalScore,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    (SELECT COUNT(*) FROM Comments WHERE UserId = tc.Id AND CreationDate >= NOW() - INTERVAL '1 month') AS RecentComments
FROM TopContributors tc
LEFT JOIN UserBadges ub ON tc.Id = ub.UserId
WHERE tc.Rank <= 10
ORDER BY tc.TotalScore DESC;
