-- {"query": "31083.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 671} 
WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
        SUM(CASE WHEN c.Id IS NOT NULL THEN 1 ELSE 0 END) AS TotalComments
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    WHERE 
        u.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
    GROUP BY 
        u.Id, u.DisplayName, u.Reputation
),
PostMetrics AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.ViewCount,
        p.Score,
        COUNT(v.Id) AS VoteCount,
        COUNT(c.Id) AS CommentCount
    FROM 
        Posts p
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.ViewCount, p.Score
),
TopUsers AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.TotalPosts,
        ua.TotalQuestions,
        ua.TotalAnswers,
        ua.Upvotes,
        ua.Downvotes,
        ua.TotalComments,
        ROW_NUMBER() OVER (ORDER BY ua.Reputation DESC) AS Rank
    FROM 
        UserActivity ua
    WHERE 
        ua.TotalPosts > 0
    ORDER BY 
        ua.Reputation DESC
    LIMIT 10
),
RecentPosts AS (
    SELECT 
        pm.PostId,
        pm.Title,
        pm.CreationDate,
        pm.ViewCount,
        pm.Score,
        pm.VoteCount,
        pm.CommentCount,
        ROW_NUMBER() OVER (ORDER BY pm.CreationDate DESC) AS RecentRank
    FROM 
        PostMetrics pm
    WHERE 
        pm.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '3 months'
)
SELECT 
    tu.DisplayName AS TopUser,
    tu.Reputation,
    tu.TotalPosts,
    tu.TotalQuestions,
    tu.TotalAnswers,
    tu.Upvotes,
    tu.Downvotes,
    rp.Title AS RecentPost,
    rp.ViewCount,
    rp.Score,
    rp.VoteCount,
    rp.CommentCount
FROM 
    TopUsers tu
JOIN 
    RecentPosts rp ON tu.UserId = (SELECT OwnerUserId FROM Posts WHERE Title = rp.Title LIMIT 1)
ORDER BY 
    tu.Rank, rp.RecentRank;