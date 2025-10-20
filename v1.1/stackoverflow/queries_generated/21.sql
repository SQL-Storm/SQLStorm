-- {"query": "21.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 171} 
WITH UserPostCounts AS (
    SELECT u.DisplayName, COUNT(p.Id) AS PostCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1 AND p.CreationDate >= '2021-01-01'
    GROUP BY u.DisplayName
),
UserReputationRanks AS (
    SELECT u.DisplayName, u.Reputation,
    RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
),
Top10Users AS (
    SELECT ur.DisplayName, ur.Reputation, upc.PostCount, ur.ReputationRank
    FROM UserReputationRanks ur
    JOIN UserPostCounts upc ON ur.DisplayName = upc.DisplayName
    WHERE ur.ReputationRank <= 10
)
SELECT *
FROM Top10Users;