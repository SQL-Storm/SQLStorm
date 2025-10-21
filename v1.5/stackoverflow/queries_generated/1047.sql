-- {"query": "1047.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 613} 

WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        COUNT(c.Id) AS CommentCount,
        DENSE_RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS ScoreRank
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    WHERE 
        p.CreationDate >= NOW() - INTERVAL '1 year'
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount
),
TopPosts AS (
    SELECT 
        PostId,
        Title,
        CreationDate,
        Score,
        ViewCount,
        CommentCount
    FROM 
        RankedPosts
    WHERE 
        ScoreRank <= 10
),
UserStatistics AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(COALESCE(v.BountyAmount, 0)) AS TotalBounty
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (8, 9) -- Bounty Start and Bounty Close
    GROUP BY 
        u.Id, u.DisplayName
)
SELECT 
    up.UserId,
    up.DisplayName,
    up.PostCount,
    up.TotalBounty,
    tp.Title AS TopPostTitle,
    tp.Score AS TopPostScore,
    tp.CommentCount AS TopPostCommentCount
FROM 
    UserStatistics up
LEFT JOIN 
    TopPosts tp ON up.PostCount > 0 
ORDER BY 
    up.TotalBounty DESC,
    up.PostCount DESC
LIMIT 5;

-- Including a query for identifying users who have the highest number of comments
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    COUNT(c.Id) AS CommentCount
FROM 
    Users u
LEFT JOIN 
    Comments c ON u.Id = c.UserId
GROUP BY 
    u.Id, u.DisplayName
HAVING 
    COUNT(c.Id) > 10
ORDER BY 
    CommentCount DESC;

-- Comparing user activity over the past year against the previous year
SELECT 
    u.DisplayName,
    SUM(CASE WHEN YEAR(c.CreationDate) = YEAR(NOW()) THEN 1 ELSE 0 END) AS CurrentYearComments,
    SUM(CASE WHEN YEAR(c.CreationDate) = YEAR(NOW()) - 1 THEN 1 ELSE 0 END) AS PreviousYearComments
FROM 
    Users u
LEFT JOIN 
    Comments c ON u.Id = c.UserId
GROUP BY 
    u.DisplayName
ORDER BY 
    CurrentYearComments DESC, PreviousYearComments DESC;
