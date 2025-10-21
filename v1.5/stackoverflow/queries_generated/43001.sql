-- {"query": "43001.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 608} 

WITH UserReputation AS (
    SELECT 
        Id, 
        Reputation, 
        DisplayName,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS ReputationRank
    FROM 
        Users
    WHERE 
        Reputation > 10000
),
TopQuestions AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.ViewCount,
        p.AnswerCount,
        p.Score,
        u.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC) AS ViewRank
    FROM 
        Posts p
    INNER JOIN 
        UserReputation u ON p.OwnerUserId = u.Id
    WHERE 
        p.PostTypeId = 1 AND p.Score > 50 AND p.AnswerCount > 0
),
QuestionActivity AS (
    SELECT 
        p.Id AS PostId,
        COUNT(ph.Id) AS EditCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenCount
    FROM 
        Posts p
    INNER JOIN 
        PostHistory ph ON p.Id = ph.PostId
    WHERE 
        p.PostTypeId = 1
    GROUP BY 
        p.Id
),
TopContributors AS (
    SELECT 
        b.UserId,
        u.DisplayName,
        COUNT(b.Id) AS BadgeCount
    FROM 
        Badges b
    INNER JOIN 
        Users u ON b.UserId = u.Id
    WHERE 
        b.Class = 1
    GROUP BY 
        b.UserId, u.DisplayName
    ORDER BY 
        BadgeCount DESC
    LIMIT 10
)
SELECT 
    u.DisplayName AS TopUser,
    u.Reputation,
    q.Title,
    q.ViewCount,
    q.AnswerCount,
    q.Score,
    qa.EditCount,
    qa.CloseCount,
    qa.ReopenCount
FROM 
    UserReputation u
INNER JOIN 
    TopQuestions q ON u.Id = q.OwnerUserId
INNER JOIN 
    QuestionActivity qa ON q.Id = qa.PostId
WHERE 
    u.ReputationRank <= 10 AND q.ViewRank <= 10
ORDER BY 
    u.Reputation DESC, q.ViewCount DESC;
