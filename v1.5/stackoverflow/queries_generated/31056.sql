-- {"query": "31056.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 332} 

WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.CreationDate,
        COUNT(c.Id) AS CommentCount,
        AVG(v.BountyAmount) AS AverageBounty,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS Rank
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8 -- BountyStart
    WHERE 
        p.PostTypeId IN (1, 2) -- Only Questions and Answers
    GROUP BY 
        p.Id, p.Title, p.Score, p.CreationDate, p.OwnerUserId
),
TopPosts AS (
    SELECT 
        rp.PostId,
        rp.Title,
        rp.Score,
        rp.CreationDate,
        rp.CommentCount,
        rp.AverageBounty
    FROM 
        RankedPosts rp
    WHERE 
        rp.Rank <= 5 
)
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    COUNT(tp.PostId) AS TotalTopPosts,
    SUM(tp.CommentCount) AS TotalComments,
    SUM(tp.AverageBounty) AS TotalBounty
FROM 
    Users u
LEFT JOIN 
    TopPosts tp ON u.Id = tp.OwnerUserId
GROUP BY 
    u.Id, u.DisplayName
ORDER BY 
    TotalTopPosts DESC, TotalComments DESC, TotalBounty DESC;
