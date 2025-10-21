-- {"query": "58070.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 968} 

WITH UserPostCounts AS (
    SELECT 
        OwnerUserId AS UserId, 
        COUNT(*) AS PostCount,
        AVG(Score) AS AvgPostScore
    FROM Posts
    WHERE CreationDate >= NOW() - INTERVAL '1 YEAR'
    GROUP BY OwnerUserId
    HAVING COUNT(*) > 100
)
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    upc.PostCount,
    upc.AvgPostScore,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id) AND v.VoteTypeId = 2) AS TotalUpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id) AND v.VoteTypeId = 3) AS TotalDownVotes,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id AND c.CreationDate >= NOW() - INTERVAL '1 YEAR') AS RecentComments,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
    RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
FROM Users u
INNER JOIN UserPostCounts upc ON u.Id = upc.UserId
INNER JOIN Badges b ON u.Id = b.UserId AND b.Date >= NOW() - INTERVAL '1 YEAR'
WHERE u.Reputation > 10000
    AND EXISTS (
        SELECT 1 
        FROM Posts p 
        WHERE p.OwnerUserId = u.Id 
            AND p.PostTypeId = 1 
            AND p.AcceptedAnswerId IS NOT NULL
    )
ORDER BY 
    upc.PostCount DESC, 
    TotalUpVotes DESC, 
    ReputationRank ASC
LIMIT 50;
