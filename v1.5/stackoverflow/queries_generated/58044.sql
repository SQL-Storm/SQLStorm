-- {"query": "58044.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1498} 

WITH UserBadgeStats AS (
    SELECT UserId, Class, COUNT(*) AS BadgeCount
    FROM Badges
    WHERE Class IN (1, 2, 3)
    GROUP BY UserId, Class
), PostMetrics AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS Downvotes,
        COUNT(DISTINCT c.Id) AS CommentCount,
        (SELECT AVG(AnswerCount) FROM Posts WHERE PostTypeId = 1 AND CreationDate >= NOW() - INTERVAL '1 YEAR') AS AvgAnnualAnswers
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId = 1 AND p.CreationDate >= NOW() - INTERVAL '5 YEARS'
    GROUP BY p.Id, p.OwnerUserId, p.Score
), BountyMax AS (
    SELECT PostId, MAX(BountyAmount) AS MaxBounty
    FROM Votes
    WHERE VoteTypeId = 8
    GROUP BY PostId
)
SELECT 
    u.Id AS UserId,
    u.Reputation,
    u.CreationDate,
    u.DisplayName,
    pm.PostId,
    pm.Score,
    pm.Upvotes,
    pm.Downvotes,
    pm.CommentCount,
    pm.AvgAnnualAnswers,
    bs.BadgeCount,
    bs.Class AS BadgeClass,
    ph.CreationDate AS LastEditDate,
    bm.MaxBounty,
    RANK() OVER (PARTITION BY bs.Class ORDER BY u.Reputation DESC) AS ReputationRank
FROM Users u
INNER JOIN UserBadgeStats bs ON u.Id = bs.UserId
INNER JOIN PostMetrics pm ON u.Id = pm.OwnerUserId
LEFT JOIN PostHistory ph ON pm.PostId = ph.PostId AND ph.PostHistoryTypeId IN (5, 6, 7)
LEFT JOIN BountyMax bm ON pm.PostId = bm.PostId
WHERE u.Reputation > 10000 AND pm.Score > 50 AND bs.BadgeCount > 10
GROUP BY 
    u.Id, u.Reputation, u.CreationDate, u.DisplayName, pm.PostId, pm.Score, pm.Upvotes, 
    pm.Downvotes, pm.CommentCount, pm.AvgAnnualAnswers, bs.BadgeCount, bs.Class, ph.CreationDate, bm.MaxBounty
HAVING COUNT(ph.Id) > 5
ORDER BY u.Reputation DESC, pm.Score DESC
LIMIT 100;
