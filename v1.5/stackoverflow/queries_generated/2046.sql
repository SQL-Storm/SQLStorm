-- {"query": "2046.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 463} 

WITH RecentPosts AS (
    SELECT 
        p.Id, 
        p.CreationDate, 
        p.Score, 
        p.OwnerUserId,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS RowNum
    FROM Posts p
    WHERE p.CreationDate > NOW() - INTERVAL '30 days'
),
TopUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(b.Id) AS BadgeCount
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(b.Id) > 5
),
PostInteractions AS (
    SELECT
        p.Id AS PostId,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) AS VoteCount
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE c.UserId IS NOT NULL OR v.UserId IS NOT NULL
    GROUP BY p.Id
)
SELECT 
    tp.DisplayName AS TopUserName,
    rp.CreationDate AS MostRecentPostDate,
    pthread.CommentCount,
    pthread.VoteCount,
    COALESCE(pscore.Score * 1.0 / NULLIF(pv.CountVotes, 0), 0) AS ScorePerVote
FROM TopUsers tp
JOIN RecentPosts rp ON tp.Id = rp.OwnerUserId AND rp.RowNum = 1
LEFT JOIN PostInteractions pthread ON rp.Id = pthread.PostId
LEFT JOIN (
    SELECT PostId, SUM(CASE WHEN VoteTypeId = 2 THEN 1 WHEN VoteTypeId = 3 THEN -1 ELSE 0 END) AS CountVotes
    FROM Votes
    GROUP BY PostId
) pv ON rp.Id = pv.PostId
LEFT JOIN (
    SELECT Id, Score
    FROM Posts
) pscore ON rp.Id = pscore.Id
ORDER BY tp.Reputation DESC, rp.CreationDate DESC;
