-- {"query": "13038.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 581} 
WITH UserReputation AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    WHERE u.Reputation > 1000 AND u.DisplayName IS NOT NULL
),
TopPosts AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Title,
        COUNT(c.Id) AS CommentCount,
        DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS UserPostRank
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId = 1 AND p.ClosedDate IS NULL
    GROUP BY p.Id, p.OwnerUserId, p.Score, p.ViewCount, p.Title
),
RecentActivity AS (
    SELECT 
        ph.PostId,
        MAX(ph.CreationDate) AS LastActivityDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (5, 10, 12)
    GROUP BY ph.PostId
)
SELECT 
    ur.UserId,
    ur.DisplayName,
    ur.Reputation,
    tp.PostId,
    tp.Title,
    tp.Score,
    tp.ViewCount,
    tp.CommentCount,
    ra.LastActivityDate,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = ur.UserId AND b.Class = 1) AS GoldBadges,
    CASE 
        WHEN ur.Reputation > 10000 THEN 'High'
        WHEN ur.Reputation BETWEEN 1000 AND 10000 THEN 'Medium'
        ELSE 'Low'
    END AS ReputationCategory,
    COALESCE(
        (SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = ur.UserId AND p.PostTypeId = 2),
        0
    ) AS AvgAnswerScore
FROM UserReputation ur
JOIN TopPosts tp ON ur.UserId = tp.OwnerUserId
LEFT JOIN RecentActivity ra ON tp.PostId = ra.PostId
WHERE tp.UserPostRank <= 5
ORDER BY ur.ReputationRank, tp.UserPostRank, ra.LastActivityDate DESC;