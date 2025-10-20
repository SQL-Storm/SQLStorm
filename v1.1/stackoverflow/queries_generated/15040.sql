-- {"query": "15040.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 95735, "output_tokens": 28528} 
WITH UserBadgeStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        AVG(COALESCE(p.Score, 0)) AS AvgPostScore,
        ROW_NUMBER() OVER (PARTITION BY b.Class ORDER BY COUNT(b.Id) DESC) AS BadgeClassRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 100
    GROUP BY u.Id, u.DisplayName
),
PostInteractions AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.PostTypeId,
        COUNT(DISTINCT v.UserId) AS UniqueVoters,
        COUNT(DISTINCT c.Id) AS CommentCount,
        (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id OR pl.RelatedPostId = p.Id) AS TotalLinks
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.CreationDate > TIMESTAMP '2010-01-01'
    GROUP BY p.Id, p.Title, p.PostTypeId
)
SELECT 
    ubs.UserId,
    ubs.DisplayName,
    ubs.TotalBadges,
    ubs.GoldBadges,
    ubs.AvgPostScore,
    pi.PostId,
    pi.Title,
    pi.UniqueVoters,
    pi.CommentCount,
    pi.TotalLinks,
    DENSE_RANK() OVER (ORDER BY ubs.TotalBadges DESC) AS BadgeRank,
    CASE 
        WHEN pi.UniqueVoters > 10 AND ubs.AvgPostScore > 5 THEN 'High Impact'
        WHEN pi.UniqueVoters > 5 THEN 'Moderate Impact'
        ELSE 'Low Impact'
    END AS UserContributionTier
FROM UserBadgeStats ubs
JOIN PostInteractions pi ON ubs.UserId = (SELECT OwnerUserId FROM Posts WHERE Id = pi.PostId)
WHERE 
    ubs.BadgeClassRank <= 100 
    AND pi.PostTypeId IN (1, 2)
    AND pi.CommentCount > 0
ORDER BY 
    ubs.TotalBadges DESC,
    pi.UniqueVoters DESC
LIMIT 500;