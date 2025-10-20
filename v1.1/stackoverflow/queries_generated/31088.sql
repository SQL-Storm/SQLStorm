-- {"query": "31088.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 314} 

WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        SUM(v.BountyAmount) AS TotalBounty,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Comments c ON u.Id = c.UserId
    LEFT JOIN 
        Votes v ON u.Id = v.UserId
    GROUP BY 
        u.Id
),
ActiveUsers AS (
    SELECT 
        UserId,
        DisplayName,
        TotalPosts,
        TotalComments,
        TotalBounty,
        Upvotes,
        Downvotes,
        RANK() OVER (ORDER BY TotalPosts DESC, Upvotes DESC, TotalBounty DESC) AS UserRank
    FROM 
        UserActivity
    WHERE 
        TotalPosts > 0
)
SELECT 
    au.DisplayName,
    au.TotalPosts,
    au.TotalComments,
    au.TotalBounty,
    au.Upvotes,
    au.Downvotes,
    au.UserRank
FROM 
    ActiveUsers au
WHERE 
    au.UserRank <= 10
ORDER BY 
    au.UserRank;
