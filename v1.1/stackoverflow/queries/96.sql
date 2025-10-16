-- {"query": "96.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 185} 
WITH RankedUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation, 
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS Rank
    FROM Users u
),
TopUserBadges AS (
    SELECT b.* 
    FROM Badges b
    JOIN RankedUsers ru ON ru.Id = b.UserId
    WHERE ru.Rank <= 10
),
TopUserPosts AS (
    SELECT p.*
    FROM Posts p
    JOIN TopUserBadges tub ON tub.UserId = p.OwnerUserId
)
SELECT u.DisplayName, COUNT(DISTINCT p.Id) AS NumPosts, SUM(p.Score) AS TotalScore,
       MAX(ph.CreationDate) AS LastPostHistory
FROM Users u
JOIN TopUserPosts p ON u.Id = p.OwnerUserId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
GROUP BY u.DisplayName
ORDER BY TotalScore DESC;