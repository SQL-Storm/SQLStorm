WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
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