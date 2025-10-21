-- {"query": "32007.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 335} 

WITH ActiveUsers AS (
    SELECT u.Id AS UserId, u.DisplayName, COUNT(p.Id) AS PostCount
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(p.Id) > 50
),
TopPosts AS (
    SELECT p.Id AS PostId, p.Title, SUM(v.BountyAmount) AS TotalBounty, p.CreationDate, p.Score
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId = 9
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.Title, p.CreationDate, p.Score
    HAVING SUM(v.BountyAmount) IS NOT NULL
),
UserBadgeCounts AS (
    SELECT b.UserId, COUNT(*) AS BadgeCount
    FROM Badges b
    WHERE b.Class = 1
    GROUP BY b.UserId
)
SELECT a.UserId, a.DisplayName, a.PostCount, ub.BadgeCount, tp.PostId, tp.Title, tp.TotalBounty, tp.CreationDate, tp.Score
FROM ActiveUsers a
JOIN UserBadgeCounts ub ON a.UserId = ub.UserId
JOIN TopPosts tp ON tp.PostId IN (
    SELECT DISTINCT PostId
    FROM Posts
    WHERE OwnerUserId = a.UserId
)
WHERE ub.BadgeCount > 5
ORDER BY tp.TotalBounty DESC, tp.CreationDate DESC;
