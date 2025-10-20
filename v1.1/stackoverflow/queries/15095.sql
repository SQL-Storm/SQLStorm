-- {"query": "15095.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 224160, "output_tokens": 66119} 
WITH UserBadgeStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        AVG(p.Score) AS AvgPostScore,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT b.Id) DESC) AS BadgeRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 100
    GROUP BY u.Id, u.DisplayName
), PostInteractions AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        v.VoteTypeId,
        COUNT(DISTINCT v.Id) AS VoteCount,
        DENSE_RANK() OVER (PARTITION BY p.Tags ORDER BY p.Score DESC) AS TagScoreRank
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.Title, p.Score, p.Tags, v.VoteTypeId
)
SELECT 
    ubs.UserId,
    ubs.DisplayName,
    ubs.TotalBadges,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.AvgPostScore,
    pi.Title,
    pi.Score AS PostScore,
    pi.VoteCount,
    COALESCE(pi.TagScoreRank, 0) AS TagRank,
    (SELECT COUNT(*) 
     FROM Comments c 
     WHERE c.UserId = ubs.UserId) AS CommentCount,
    CASE 
        WHEN ubs.TotalBadges > 10 AND pi.Score > 50 THEN 'High Impact User'
        WHEN ubs.TotalBadges BETWEEN 5 AND 10 AND pi.Score > 25 THEN 'Emerging Contributor'
        ELSE 'Regular User'
    END AS UserCategory
FROM UserBadgeStats ubs
JOIN PostInteractions pi ON 1=1
WHERE pi.Score > 0
    AND (pi.VoteCount > 5 OR ubs.TotalBadges > 5)
    AND (ubs.AvgPostScore IS NULL OR ubs.AvgPostScore > 0)
ORDER BY ubs.TotalBadges DESC, pi.Score DESC
LIMIT 1000;