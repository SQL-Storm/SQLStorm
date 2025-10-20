-- {"query": "58040.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 856} 
WITH ActiveUsers AS (
    SELECT Id, DisplayName, Reputation
    FROM Users
    WHERE Reputation > 10000
    AND LastAccessDate >= '2023-01-01'
)
SELECT 
    au.Id AS UserId,
    au.DisplayName,
    au.Reputation,
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND LENGTH(c.Text) > 100) AS LongComments,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS Upvotes,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = au.Id AND b.Class = 1) AS GoldBadges,
    RANK() OVER (PARTITION BY au.Id ORDER BY p.Score DESC) AS PostRank
FROM ActiveUsers au
JOIN Posts p ON au.Id = p.OwnerUserId
JOIN PostHistory ph ON p.Id = ph.PostId
LEFT JOIN Tags t ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
WHERE p.PostTypeId = 1
AND p.CreationDate BETWEEN '2022-01-01' AND '2022-12-31'
AND p.Score > 50
AND t.TagName IN ('java', 'python', 'sql', 'javascript')
GROUP BY au.Id, au.DisplayName, au.Reputation, p.Id, p.Title, p.Score, p.ViewCount
HAVING COUNT(ph.Id) > 5
ORDER BY GoldBadges DESC, Upvotes DESC, PostRank ASC
LIMIT 100;