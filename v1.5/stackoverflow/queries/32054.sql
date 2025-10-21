-- {"query": "32054.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 332} 
WITH UserReputationStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END), 0) AS UpVotesCount,
        COALESCE(SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END), 0) AS DownVotesCount
    FROM Users u
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopUsersByReputation AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        UpVotesCount,
        DownVotesCount,
        RANK() OVER (ORDER BY Reputation DESC) AS RankByReputation
    FROM UserReputationStats
)
SELECT 
    tur.UserId,
    tur.DisplayName,
    tur.Reputation,
    tur.UpVotesCount,
    tur.DownVotesCount,
    tur.RankByReputation,
    b.Name AS BadgeName,
    COUNT(b.Id) AS BadgeCount
FROM TopUsersByReputation tur
LEFT JOIN Badges b ON tur.UserId = b.UserId
WHERE tur.RankByReputation <= 100
GROUP BY tur.UserId, tur.DisplayName, tur.Reputation, tur.UpVotesCount, tur.DownVotesCount, tur.RankByReputation, b.Name
ORDER BY tur.RankByReputation, BadgeCount DESC, b.Name;