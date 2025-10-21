-- {"query": "58007.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1209} 

WITH ActiveUsers AS (
    SELECT 
        u.Id, 
        u.Reputation, 
        u.CreationDate, 
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Class = 1
    WHERE u.CreationDate BETWEEN '2010-01-01' AND '2023-12-31'
    GROUP BY u.Id, u.Reputation, u.CreationDate
    HAVING COUNT(p.Id) > 10 AND COUNT(c.Id) > 20
),
VoteStats AS (
    SELECT 
        PostId,
        AVG(Score) OVER (PARTITION BY PostId) AS AvgScore,
        SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes
    FROM Votes
    WHERE CreationDate > (SELECT MAX(CreationDate) - INTERVAL '1 YEAR' FROM Votes)
)
SELECT 
    au.Id AS UserId,
    au.Reputation,
    au.PostCount,
    au.CommentCount,
    au.BadgeCount,
    au.ReputationRank,
    vs.AvgScore,
    vs.Upvotes,
    vs.Downvotes,
    (SELECT MAX(p.Score) FROM Posts p WHERE p.OwnerUserId = au.Id) AS HighestPostScore,
    STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, 5), ', ') AS TopTags,
    COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId = 2) AS BodyEdits
FROM ActiveUsers au
JOIN Posts p ON au.Id = p.OwnerUserId
JOIN VoteStats vs ON p.Id = vs.PostId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (2,5,8)
WHERE p.PostTypeId = 1 AND p.AnswerCount > 5
GROUP BY au.Id, au.Reputation, au.PostCount, au.CommentCount, au.BadgeCount, au.ReputationRank, vs.AvgScore, vs.Upvotes, vs.Downvotes
ORDER BY au.ReputationRank, HighestPostScore DESC, vs.Upvotes DESC
LIMIT 1000;
