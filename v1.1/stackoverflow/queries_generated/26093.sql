-- {"query": "26093.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 659} 

WITH RECURSIVE PostHierarchy AS (
    SELECT Id, ParentId, 0 AS Level
    FROM Posts
    WHERE ParentId IS NULL
    UNION ALL
    SELECT p.Id, p.ParentId, Level + 1
    FROM Posts p
    JOIN PostHierarchy ph ON p.ParentId = ph.Id
),
UserReputation AS (
    SELECT u.Id, SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) AS ReputationChange
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON p.Id = v.PostId
    GROUP BY u.Id
),
TopPosts AS (
    SELECT p.Id, p.Score, p.ViewCount, ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS RowNum
    FROM Posts p
    JOIN PostHierarchy ph ON p.Id = ph.Id
    WHERE ph.Level < 3
)
SELECT 
    p.Id,
    p.Title,
    p.Score,
    p.ViewCount,
    ph.Level,
    u.Reputation + ur.ReputationChange AS TotalReputation,
    string_agg(DISTINCT t.TagName, ', ') AS Tags,
    COUNT(DISTINCT v.Id) AS VoteCount,
    COUNT(DISTINCT c.Id) AS CommentCount,
    ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS PostRank,
    CASE 
        WHEN p.Score > 100 THEN 'High'
        WHEN p.Score > 50 THEN 'Medium'
        ELSE 'Low'
    END AS ScoreCategory,
    LAG(p.Score, 1) OVER (ORDER BY p.Score DESC) AS PrevScore,
    LEAD(p.Score, 1) OVER (ORDER BY p.Score DESC) AS NextScore,
    p.Score - LAG(p.Score, 1) OVER (ORDER BY p.Score DESC) AS ScoreDiff,
    p.Score + LEAD(p.Score, 1) OVER (ORDER BY p.Score DESC) AS ScoreSum,
    COALESCE(string_agg(DISTINCT b.Name, ', '), '') AS Badges,
    COALESCE(string_agg(DISTINCT ph2.Comment, ', '), '') AS PostHistory
FROM Posts p
JOIN PostHierarchy ph ON p.Id = ph.Id
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN UserReputation ur ON u.Id = ur.Id
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
LEFT JOIN Tags t ON pl.RelatedPostId = t.Id
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN PostHistory ph2 ON p.Id = ph2.PostId
WHERE p.PostTypeId = 1 AND p.Score > 0
GROUP BY p.Id, p.Title, p.Score, p.ViewCount, ph.Level, u.Reputation, ur.ReputationChange
HAVING COUNT(DISTINCT v.Id) > 10 AND COUNT(DISTINCT c.Id) > 5
ORDER BY p.Score DESC;
