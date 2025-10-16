-- {"query": "15020.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 49035, "output_tokens": 14546} 
WITH UserBadgeStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS MedianPostScore,
        RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 100
    GROUP BY u.Id, u.DisplayName
),
TopQuestionTags AS (
    SELECT 
        unnest(string_to_array(substring(Tags, 2, length(Tags)-2), '><')) AS Tag,
        AVG(ViewCount) AS AvgViewCount,
        COUNT(*) AS TagQuestionCount
    FROM Posts
    WHERE PostTypeId = 1
    GROUP BY Tag
    HAVING COUNT(*) > 50
)
SELECT 
    ubs.UserId,
    ubs.DisplayName,
    ubs.TotalBadges,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.MedianPostScore,
    tqt.Tag AS MostPopularTag,
    tqt.AvgViewCount,
    (SELECT COUNT(*) 
     FROM Comments c 
     WHERE c.UserId = ubs.UserId) AS TotalComments,
    CASE 
        WHEN ubs.ReputationRank <= 100 THEN 'Top 100 User'
        WHEN ubs.ReputationRank <= 1000 THEN 'Top 1000 User'
        ELSE 'Regular User'
    END AS UserTier
FROM UserBadgeStats ubs
JOIN TopQuestionTags tqt ON 1=1
WHERE ubs.TotalBadges > 5 
    AND (ubs.MedianPostScore > 0 OR EXISTS (
        SELECT 1 
        FROM Votes v 
        WHERE v.UserId = ubs.UserId AND v.VoteTypeId IN (2, 8)
    ))
ORDER BY ubs.TotalBadges DESC, ubs.ReputationRank
LIMIT 100;