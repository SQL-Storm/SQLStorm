-- {"query": "45003.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 6882, "output_tokens": 1142} 
WITH UserActivityRanking AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName, 
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        RANK() OVER (ORDER BY u.Reputation DESC, COUNT(DISTINCT p.Id) DESC) AS UserRank,
        AVG(p.Score) AS AveragePostScore
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Votes v ON u.Id = v.UserId
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    WHERE 
        u.Reputation > 1000
        AND p.CreationDate > '2015-01-01'
    GROUP BY 
        u.Id, u.DisplayName, u.Reputation
)
SELECT 
    UserRank,
    DisplayName,
    Reputation,
    PostCount,
    VoteCount,
    BadgeCount,
    AveragePostScore,
    DENSE_RANK() OVER (ORDER BY PostCount DESC) AS PostCountRank,
    DENSE_RANK() OVER (ORDER BY VoteCount DESC) AS VoteCountRank
FROM 
    UserActivityRanking
WHERE 
    UserRank <= 100
ORDER BY 
    UserRank, PostCount DESC
LIMIT 50;