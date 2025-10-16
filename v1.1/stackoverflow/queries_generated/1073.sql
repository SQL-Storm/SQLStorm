-- {"query": "1073.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 493} 

WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(v.VoteTypeId = 2) AS Upvotes,
        SUM(v.VoteTypeId = 3) AS Downvotes,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS UserRank
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Comments c ON u.Id = c.UserId
    LEFT JOIN 
        Votes v ON u.Id = v.UserId
    GROUP BY 
        u.Id, u.Reputation
),
TopUsers AS (
    SELECT 
        UserId,
        Reputation,
        PostCount,
        CommentCount,
        Upvotes,
        Downvotes,
        UserRank
    FROM 
        UserActivity
    WHERE 
        UserRank <= 10
),
PostsWithComments AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        COALESCE(c.CommentCount, 0) AS CommentCount
    FROM 
        Posts p
    LEFT JOIN (
        SELECT 
            PostId, COUNT(*) AS CommentCount 
        FROM 
            Comments 
        GROUP BY PostId
    ) c ON p.Id = c.PostId
)
SELECT 
    tu.UserId,
    tu.Reputation,
    tu.PostCount,
    tu.CommentCount,
    tu.Upvotes,
    tu.Downvotes,
    pwc.PostId,
    pwc.Title,
    pwc.CreationDate,
    pwc.Score,
    pwc.CommentCount,
    CASE 
        WHEN pwc.Score >= 10 THEN 'High Scoring'
        WHEN pwc.Score BETWEEN 5 AND 9 THEN 'Medium Scoring'
        ELSE 'Low Scoring'
    END AS ScoreCategory,
    ROW_NUMBER() OVER (PARTITION BY tu.UserId ORDER BY pwc.CreationDate DESC) AS PostRank
FROM 
    TopUsers tu
JOIN 
    PostsWithComments pwc ON tu.PostCount > 0 
WHERE 
    tu.PostCount > 0
ORDER BY 
    tu.Reputation DESC, 
    pwc.CreationDate DESC;
