-- {"query": "15031.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 631}
WITH UserBadgeCounts AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName,
        COUNT(DISTINCT b.Id) AS GoldBadgeCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        COALESCE(
            NULLIF(
                AVG(p.Score) OVER (PARTITION BY u.Id ORDER BY u.Reputation 
                ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING), 
            0), 
            0
        ) AS AvgPostScore
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Class = 1
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > (
        SELECT AVG(Reputation) 
        FROM Users 
        WHERE CreationDate > TIMESTAMP '2010-01-01'
    )
), TopContributors AS (
    SELECT 
        UserId,
        DisplayName,
        GoldBadgeCount,
        RANK() OVER (ORDER BY GoldBadgeCount DESC) AS BadgeRank,
        AvgPostScore
    FROM UserBadgeCounts
    WHERE VoteCount > 10
)
SELECT 
    tc.UserId,
    tc.DisplayName,
    tc.GoldBadgeCount,
    tc.BadgeRank,
    p.Tags,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId IN (
        SELECT Id FROM Posts WHERE OwnerUserId = tc.UserId
    )) AS RelatedPostLinksCount,
    CASE 
        WHEN tc.AvgPostScore > 10 THEN 'High Impact'
        WHEN tc.AvgPostScore > 5 THEN 'Moderate Impact'
        ELSE 'Low Impact'
    END AS ContributionQuality
FROM TopContributors tc
JOIN Posts p ON p.OwnerUserId = tc.UserId
WHERE tc.BadgeRank <= 100
    AND p.PostTypeId = 1
    AND LENGTH(p.Tags) > 0
GROUP BY 
    tc.UserId, 
    tc.DisplayName, 
    tc.GoldBadgeCount, 
    tc.BadgeRank, 
    p.Tags,
    tc.AvgPostScore
ORDER BY 
    tc.GoldBadgeCount DESC,
    tc.BadgeRank
LIMIT 50;
