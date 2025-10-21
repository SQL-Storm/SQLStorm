-- {"query": "58073.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1076} 
WITH ActiveUsers AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        u.Reputation, 
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT b.Id) AS TotalBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1 AND p.CreationDate >= '2023-01-01'
    LEFT JOIN Comments c ON u.Id = c.UserId AND c.CreationDate >= '2023-01-01'
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Date >= '2023-01-01'
    WHERE u.Reputation > 1000 AND u.LastAccessDate >= '2023-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 10 OR COUNT(DISTINCT c.Id) > 50
),
PostStats AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.Tags,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        COUNT(DISTINCT ph.Id) AS EditHistoryCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.CreationDate >= '2023-01-01'
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (5,6,7,8,9)
    WHERE p.PostTypeId = 1 AND p.CreationDate BETWEEN '2023-01-01' AND '2023-12-31'
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, p.Tags
)
SELECT 
    au.DisplayName,
    au.Reputation,
    au.TotalPosts,
    au.TotalComments,
    au.TotalBadges,
    ps.Title,
    ps.Score AS PostScore,
    ps.ViewCount,
    ps.AnswerCount,
    ps.Tags,
    ps.TotalVotes,
    ps.Upvotes,
    ps.Downvotes,
    ps.EditHistoryCount,
    RANK() OVER (ORDER BY ps.Score DESC) AS PostRank,
    DENSE_RANK() OVER (PARTITION BY au.Id ORDER BY ps.ViewCount DESC) AS UserPostViewRank,
    AVG(ps.Score) OVER (PARTITION BY au.Id) AS AvgUserPostScore
FROM ActiveUsers au
JOIN Posts p ON au.Id = p.OwnerUserId
JOIN PostStats ps ON p.Id = ps.PostId
WHERE ps.AnswerCount > 5 AND ps.ViewCount > 1000
ORDER BY 
    au.Reputation DESC, 
    ps.Score DESC, 
    ps.ViewCount DESC
LIMIT 1000;