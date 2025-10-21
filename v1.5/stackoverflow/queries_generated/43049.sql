-- {"query": "43049.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 608} 

WITH TopUsers AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id
    HAVING COUNT(DISTINCT b.Id) > 0
    ORDER BY u.Reputation DESC, TotalBadges DESC
    LIMIT 10
),
HighlyEngagedPosts AS (
    SELECT 
        p.Id,
        p.Title,
        p.ViewCount,
        p.Score,
        p.AnswerCount,
        p.CommentCount,
        p.OwnerUserId,
        ph.CreationDate AS LastEditDate
    FROM Posts p
    JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE p.PostTypeId = 1 AND p.Score > 50 AND p.ViewCount > 1000
    ORDER BY ph.CreationDate DESC
    LIMIT 100
),
TopContributors AS (
    SELECT 
        p.OwnerUserId,
        COUNT(p.Id) AS TotalPosts,
        SUM(p.Score) AS TotalScore,
        AVG(p.ViewCount) AS AvgViewCount
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) AND p.Score > 0
    GROUP BY p.OwnerUserId
    ORDER BY TotalScore DESC
    LIMIT 5
)
SELECT 
    u.DisplayName,
    u.Reputation,
    tu.TotalBadges,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    hep.Title,
    hep.ViewCount,
    hep.Score,
    hep.AnswerCount,
    hep.CommentCount,
    hep.LastEditDate,
    tc.TotalPosts,
    tc.TotalScore,
    tc.AvgViewCount
FROM TopUsers tu
JOIN HighlyEngagedPosts hep ON tu.Id = hep.OwnerUserId
JOIN TopContributors tc ON tu.Id = tc.OwnerUserId
ORDER BY tu.Reputation DESC, hep.Score DESC, tc.TotalScore DESC;
