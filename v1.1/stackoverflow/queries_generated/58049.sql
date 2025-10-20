-- {"query": "58049.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1059} 

WITH AvgPostScore AS (
    SELECT AVG(Score) AS AvgScore
    FROM Posts
    WHERE PostTypeId = 1
), RankedUsers AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) AS PostCount,
        RANK() OVER (ORDER BY COUNT(p.Id) DESC) AS ActivityRank
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1
      AND p.CreationDate BETWEEN '2020-01-01' AND '2023-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(p.Id) > 10
)
SELECT 
    ru.DisplayName,
    ru.Reputation,
    ru.PostCount,
    ru.ActivityRank,
    COUNT(DISTINCT c.Id) AS TotalComments,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = ru.Id AND b.Class = 1) AS GoldBadges,
    ARRAY_LENGTH(STRING_TO_ARRAY(REPLACE(REPLACE(p.Tags, '><', ','), '<>', ''), ','), 1) AS TagCount,
    ph.Edits,
    CASE WHEN p.Score > aps.AvgScore THEN 'Above Avg' ELSE 'Below Avg' END AS ScoreStatus
FROM RankedUsers ru
JOIN Posts p ON ru.Id = p.OwnerUserId
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN (
    SELECT 
        PostId,
        COUNT(*) AS Edits
    FROM PostHistory
    WHERE PostHistoryTypeId = 5
    GROUP BY PostId
) ph ON p.Id = ph.PostId
CROSS JOIN AvgPostScore aps
WHERE p.PostTypeId = 1
  AND p.AnswerCount > 3
  AND p.ClosedDate IS NULL
GROUP BY 
    ru.DisplayName, 
    ru.Reputation, 
    ru.PostCount, 
    ru.ActivityRank, 
    p.Tags, 
    ph.Edits, 
    p.Score, 
    aps.AvgScore
ORDER BY 
    ru.ActivityRank ASC, 
    TotalComments DESC, 
    Upvotes DESC
LIMIT 100;
