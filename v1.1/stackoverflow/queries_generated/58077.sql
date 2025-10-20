-- {"query": "58077.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1025} 

WITH ActiveUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation, u.CreationDate,
           COUNT(DISTINCT p.Id) AS TotalPosts,
           COUNT(DISTINCT c.Id) AS TotalComments,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RankByReputation
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId IN (1, 2)
    LEFT JOIN Comments c ON u.Id = c.UserId
    WHERE u.Reputation > 10000
      AND p.CreationDate BETWEEN '2022-01-01' AND '2023-12-31'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
    HAVING COUNT(p.Id) > 50
),
VoteAnalysis AS (
    SELECT v.UserId,
           SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
           SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes,
           AVG(v.BountyAmount) FILTER (WHERE v.VoteTypeId = 8) AS AvgBounty
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE v.CreationDate BETWEEN '2022-01-01' AND '2023-12-31'
    GROUP BY v.UserId
),
BadgeSummary AS (
    SELECT b.UserId,
           STRING_AGG(b.Name, ', ' ORDER BY b.Date) AS BadgeNames,
           COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges
    FROM Badges b
    WHERE b.Date BETWEEN '2022-01-01' AND '2023-12-31'
    GROUP BY b.UserId
)
SELECT au.DisplayName, au.Reputation, au.TotalPosts, au.TotalComments,
       va.UpVotes, va.DownVotes, va.AvgBounty,
       bs.BadgeNames, bs.GoldBadges,
       (SELECT AVG(Score) FROM Posts WHERE OwnerUserId = au.Id) AS AvgPostScore,
       (SELECT MAX(Score) FROM Comments WHERE UserId = au.Id) AS MaxCommentScore,
       DENSE_RANK() OVER (ORDER BY au.TotalPosts + au.TotalComments DESC) AS ActivityRank
FROM ActiveUsers au
JOIN VoteAnalysis va ON au.Id = va.UserId
LEFT JOIN BadgeSummary bs ON au.Id = bs.UserId
WHERE au.RankByReputation <= 100
ORDER BY au.Reputation DESC, ActivityRank
LIMIT 500;
