-- {"query": "58087.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1112} 
WITH TopUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation, COUNT(b.Id) AS GoldBadges
    FROM Users u
    JOIN Badges b ON u.Id = b.UserId AND b.Class = 1
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(b.Id) >= 5
)
SELECT 
    tu.DisplayName,
    p.Title AS TopQuestion,
    (SELECT AVG(Score) FROM Posts p2 WHERE p2.OwnerUserId = tu.Id AND p2.PostTypeId = 2) AS AvgAnswerScore,
    COUNT(DISTINCT c.Id) AS TotalComments,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
    RANK() OVER (ORDER BY tu.Reputation DESC) AS ReputationRank,
    STRING_AGG(DISTINCT ph.Text, '; ') AS RecentHistoryActions,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS DuplicateLinks
FROM TopUsers tu
JOIN Posts p ON tu.Id = p.OwnerUserId AND p.PostTypeId = 1
LEFT JOIN Comments c ON p.Id = c.PostId AND c.CreationDate > cast('2024-10-01' as date) - INTERVAL '1 year'
LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 5)
LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId BETWEEN 4 AND 6
WHERE p.CreationDate > cast('2024-10-01' as date) - INTERVAL '2 years'
    AND p.Tags LIKE '%<sql>%'
    AND p.AnswerCount > 3
GROUP BY tu.Id, tu.DisplayName, tu.Reputation, p.Id, p.Title
HAVING COUNT(DISTINCT v.Id) > 10 AND AVG(p.Score) >= 5
ORDER BY tu.Reputation DESC, TotalComments DESC, Upvotes DESC
LIMIT 100;